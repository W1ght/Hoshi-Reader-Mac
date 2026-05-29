# Reader Fixture Sources

This directory is reserved for small, deterministic Reader regression fixture sources.

Generated EPUB files should be written by:

```bash
python3 script/generate_reader_fixtures.py
```

Default output:

```text
testdata/reader-fixtures/
```

Keep fixture content synthetic and focused:

- no copyrighted book text;
- no large binary images unless explicitly approved;
- every fixture should map to a scenario in `docs/READER_REGRESSION_TESTING.md`;
- generated EPUBs should remain deterministic so screenshot regressions are attributable to Reader changes.

The current generator creates minimal EPUBs directly from embedded source templates. If fixtures become larger, move the XHTML/CSS/image source files into this directory and keep the generated EPUBs out of review unless they are intentionally committed.
