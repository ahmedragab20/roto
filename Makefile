.PHONY: fff build bundle run install test gen-emoji brand

# App search links fff (Rust) as a static library; needs cargo (rustup.rs).
fff:
	bash scripts/build-fff.sh

build: fff
	swift build -c release --product roto

bundle:
	bash scripts/bundle.sh

run: bundle
	open build/roto.app

install: bundle
	rm -rf /Applications/roto.app
	cp -R build/roto.app /Applications/roto.app

test: fff
	swift test --enable-swift-testing --disable-xctest

gen-emoji:
	swift scripts/gen-emoji.swift

brand:
	mkdir -p .build
	swiftc -O -parse-as-library -o .build/make-brand scripts/make-brand.swift Sources/RotoCore/Brand/BrandMark.swift
	.build/make-brand
