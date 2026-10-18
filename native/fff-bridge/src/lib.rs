//! The slice of fff that roto's launcher needs, as a small C API.
//!
//! roto writes one empty file per searchable item into a directory it owns
//! (the file name is what gets matched), and this bridge keeps an fff index of
//! that directory. fff does the matching (typo-resistant fuzzy search) and the
//! ranking, including frecency from the launches recorded with `fff_bridge_track`.
//!
//! A panic inside fff must never take roto down with it, so every entry point
//! catches one and reports failure (NULL, false, or no results) instead.

use std::ffi::{CStr, CString, c_char, c_void};
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::path::PathBuf;
use std::time::Duration;

use fff_search::frecency::FrecencyTracker;
use fff_search::{
    FFFMode, FilePicker, FilePickerOptions, FuzzySearchOptions, PaginationArgs, QueryParser,
    SharedFilePicker, SharedFrecency,
};

pub struct Bridge {
    base: PathBuf,
    picker: SharedFilePicker,
    frecency: SharedFrecency,
}

/// Called once per result, best first. `name` is valid only during the call.
pub type MatchCallback = extern "C" fn(name: *const c_char, score: i32, context: *mut c_void);

fn guarded<T>(fallback: T, body: impl FnOnce() -> T) -> T {
    catch_unwind(AssertUnwindSafe(body)).unwrap_or(fallback)
}

unsafe fn string(ptr: *const c_char) -> Option<String> {
    if ptr.is_null() {
        return None;
    }
    unsafe { CStr::from_ptr(ptr) }
        .to_str()
        .ok()
        .filter(|s| !s.is_empty())
        .map(str::to_owned)
}

/// Indexes `base_dir` and opens the frecency database at `frecency_db`
/// (NULL to skip frecency). Returns NULL on failure. Scanning runs in the
/// background; `fff_bridge_rescan` waits for it.
///
/// # Safety
/// Both arguments are NULL or valid NUL-terminated UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fff_bridge_open(
    base_dir: *const c_char,
    frecency_db: *const c_char,
) -> *mut Bridge {
    guarded(std::ptr::null_mut(), || unsafe {
        open(base_dir, frecency_db)
    })
}

unsafe fn open(base_dir: *const c_char, frecency_db: *const c_char) -> *mut Bridge {
    let Some(base) = (unsafe { string(base_dir) }) else {
        return std::ptr::null_mut();
    };
    let picker = SharedFilePicker::default();
    let frecency = SharedFrecency::default();

    if let Some(path) = unsafe { string(frecency_db) } {
        let _ = std::fs::create_dir_all(&path);
        // A broken database only costs ranking, never search.
        if let Ok(tracker) = FrecencyTracker::open(&path) {
            let _ = frecency.init(tracker);
        }
    }

    let options = FilePickerOptions {
        base_path: base.clone(),
        enable_mmap_cache: false,
        enable_content_indexing: false,
        // roto tells the bridge when the directory changes.
        watch: false,
        mode: FFFMode::Neovim,
        ..Default::default()
    };
    if FilePicker::new_with_shared_state(picker.clone(), frecency.clone(), options).is_err() {
        return std::ptr::null_mut();
    }

    Box::into_raw(Box::new(Bridge {
        base: PathBuf::from(base),
        picker,
        frecency,
    }))
}

/// # Safety
/// `bridge` is NULL or came from `fff_bridge_open` and is not used afterwards.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fff_bridge_close(bridge: *mut Bridge) {
    if bridge.is_null() {
        return;
    }
    let bridge = unsafe { Box::from_raw(bridge) };
    guarded((), || {
        if let Ok(mut guard) = bridge.picker.write() {
            guard.take();
        }
        if let Ok(mut guard) = bridge.frecency.write() {
            guard.take();
        }
    })
}

/// Rescans the directory (or, right after `fff_bridge_open`, finishes the
/// first scan) and waits up to `timeout_ms`. Returns whether the scan finished.
///
/// # Safety
/// `bridge` came from `fff_bridge_open`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fff_bridge_rescan(
    bridge: *mut Bridge,
    timeout_ms: u64,
    full: bool,
) -> bool {
    let Some(bridge) = (unsafe { bridge.as_ref() }) else {
        return false;
    };
    guarded(false, || {
        if full
            && bridge
                .picker
                .trigger_full_rescan_async(&bridge.frecency)
                .is_err()
        {
            return false;
        }
        bridge
            .picker
            .wait_for_scan(Duration::from_millis(timeout_ms))
    })
}

/// Fuzzy-matches `query` against the indexed names and reports up to `limit`
/// results through `callback`. An empty query lists names by frecency.
/// Returns how many names matched in total.
///
/// # Safety
/// `bridge` came from `fff_bridge_open`; `query` is valid NUL-terminated UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fff_bridge_search(
    bridge: *mut Bridge,
    query: *const c_char,
    limit: u32,
    callback: MatchCallback,
    context: *mut c_void,
) -> u32 {
    let Some(bridge) = (unsafe { bridge.as_ref() }) else {
        return 0;
    };
    let query = unsafe { string(query) }.unwrap_or_default();
    guarded(0, || search(bridge, &query, limit, callback, context))
}

fn search(
    bridge: &Bridge,
    query: &str,
    limit: u32,
    callback: MatchCallback,
    context: *mut c_void,
) -> u32 {
    let Ok(guard) = bridge.picker.read() else {
        return 0;
    };
    let Some(picker) = guard.as_ref() else {
        return 0;
    };

    let parsed = QueryParser::default().parse(query);
    let results = picker.fuzzy_search(
        &parsed,
        None,
        FuzzySearchOptions {
            // A few hundred names: threads cost more than they save.
            max_threads: 1,
            current_file: None,
            project_path: Some(picker.base_path()),
            combo_boost_score_multiplier: 0,
            min_combo_count: 0,
            pagination: PaginationArgs {
                offset: 0,
                limit: limit as usize,
            },
        },
    );

    for (item, score) in results.items.iter().zip(results.scores.iter()) {
        let Ok(name) = CString::new(item.relative_path(picker).to_string()) else {
            continue;
        };
        callback(name.as_ptr(), score.total, context);
    }
    results.total_matched as u32
}

/// Records that `name` was opened, so it ranks higher next time.
///
/// # Safety
/// `bridge` came from `fff_bridge_open`; `name` is valid NUL-terminated UTF-8.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fff_bridge_track(bridge: *mut Bridge, name: *const c_char) -> bool {
    let Some(bridge) = (unsafe { bridge.as_ref() }) else {
        return false;
    };
    let Some(name) = (unsafe { string(name) }) else {
        return false;
    };
    guarded(false, || track(bridge, &name))
}

fn track(bridge: &Bridge, name: &str) -> bool {
    let path = bridge.base.join(name);

    let Ok(frecency) = bridge.frecency.read() else {
        return false;
    };
    let Some(tracker) = frecency.as_ref() else {
        return false;
    };
    if tracker.track_access(&path).is_err() {
        return false;
    }
    let Ok(mut picker) = bridge.picker.write() else {
        return false;
    };
    let Some(picker) = picker.as_mut() else {
        return false;
    };
    picker.update_single_file_frecency(&path, tracker).is_ok()
}
