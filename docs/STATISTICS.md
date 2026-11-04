# Custom statistics: manual entry and CSV import

The Custom Edition keeps the upstream tracker polling and history model. Every observation is a new immutable `Snapshot`; corrections are appended as later observations and never overwrite earlier history.

## Manual entry

Open a tracker from the dashboard and expand **Add manual statistics**.

- Uploaded and downloaded are required, non-negative integer byte counts.
- Ratio, required ratio, bonus points and torrent counts are optional. A blank field stays `NULL`; zero is a real zero.
- The observation time defaults to the current time in the signed-in user's time zone. Future timestamps are rejected.
- Notes are optional and limited to 500 characters.
- The entry is saved only to the signed-in user's own tracker connection.
- Each manual point is labelled `Manual` and records the account that entered it.

## CSV import

Open **Settings → Data → Import statistics from CSV**.

1. Download the CSV from the relevant tracker history page.
2. Keep its original header row and the ISO 8601 timestamps.
3. Optionally add a `note` column for row notes.
4. Select the matching tracker connection and upload the CSV.

The importer accepts the existing Sherlock history export columns. Required columns are `time`, `uploaded` and `downloaded`. Optional metric columns include ratio, required ratio, bonus points and torrent counts. Derived columns such as `buffer`, per-interval changes and interval ratio are ignored and recalculated from the stored history.

Safety and consistency rules:

- Maximum upload size: 50 MiB. Maximum rows: 100,000.
- UTF-8 (including a UTF-8 BOM) only; malformed CSV, duplicate headers and unknown columns are rejected.
- Byte fields must be non-negative whole numbers that fit PostgreSQL `bigint`. Counts must fit a non-negative PostgreSQL `integer`.
- Decimal values are checked against the database precision before insertion; values are never silently rounded.
- Timestamps must be ISO 8601 with an explicit timezone offset and cannot be in the future.
- Existing timestamps and duplicates within the same file are skipped. If any row is invalid, no rows from that file are inserted.
- Imported points are labelled `CSV import`, linked to the importing user, and share one import-batch UUID.

## Provenance and JSON compatibility

Snapshots carry a source (`api`, `manual`, `csv_import` or `json_import`), optional note, optional creator and optional import-batch ID. The tracker history page shows the most recent observations and their source.

The existing upstream account-data JSON export/import remains supported. Imported snapshot rows are marked `json_import` and receive a new local batch ID. Creator IDs and batch IDs are local metadata and are not exported. Tracker credentials and password data remain excluded as before.

A separate versioned Custom Edition JSON statistics interchange format, CSV preview/column mapping, and downloadable multi-row error report are still planned.
