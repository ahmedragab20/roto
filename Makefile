.PHONY: build bundle run install test gen-emoji brand

build:
	swift build -c release --product roto

bundle:
	bash scripts/bundle.sh

run: bundle
	open build/roto.app

install: bundle
	rm -rf /Applications/roto.app
	cp -R build/roto.app /Applications/roto.app

test:
	swift test --enable-swift-testing --disable-xctest

gen-emoji:
	swift scripts/gen-emoji.swift

brand:
	mkdir -p .build
	swiftc -O -parse-as-library -o .build/make-brand scripts/make-brand.swift Sources/RotoCore/Brand/BrandMark.swift
	.build/make-brand
