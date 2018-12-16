# blockstack-search-tools

A janky tool for analyzing the Blockstack network.

This code was written for a one-off purpose that has since been fulfilled,
and is provided as-is.  I published it here to show an example of how to crawl
the Blockstack network.  There are no plans to support it beyond its current
state.

All programs must be run in-place.

## Dependencies

* The `dash` shell (it will NOT work with `bash`)
* Node.js 8.x
* `blockstack.js`, installed in a place where `node` can find it.
* A Blockstack Core node running on the same host (i.e. `~/.blockstack-server`
  must exist and be populated).

## Usage

### Step 1: Scan all profiles

```bash
$ ./scan_profiles.sh
```

You may need to edit variables in `./scan_profiles.sh` to suit your needs.

All data will be written to `./results`.
* `./results/all_profiles/` contains metadata and profiles fetched, in batches.
* `./results/all_profiles_analysis/` contains analysis data for each profile
  batch.

This script uses the `check_profiles.js` command to analyze the metadata in
`./results/all_profiles`.  Feel free to extend the data it gathers for your own
purposes.

### Step 2: Make a report

```bash
$ ./report.js ./results/all_profiles_analysis/
```

This script aggregates the analysis data from `./results/all_profiles_analysis/`
and prints out a report.  Feel free to extend it to report on more things than
it already does.
