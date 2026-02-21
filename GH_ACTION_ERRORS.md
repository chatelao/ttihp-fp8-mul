# Analysis of GitHub Actions Pipeline Errors

This document identifies current errors and risks in the GitHub Actions pipeline for the Tiny Tapeout project and provides recommendations for fixing them.

## 1. Missing Checkout Steps in `gds.yaml`

**Cause:** The `precheck` and `viewer` jobs in `.github/workflows/gds.yaml` do not include an `actions/checkout` step. These jobs depend on the presence of project files (like `info.yaml`) to function correctly.
**Recommendation:** Add the `actions/checkout` step to both the `precheck` and `viewer` jobs.

```yaml
    steps:
      - name: checkout repo
        uses: actions/checkout@v4
        with:
          submodules: recursive
```

## 2. Incomplete Documentation Deployment in `docs.yaml`

**Cause:** The `.github/workflows/docs.yaml` workflow builds the documentation but lacks the necessary permissions and steps to deploy it to GitHub Pages. It also uses a potentially incorrect action path.
**Recommendation:** Add the required permissions and a deployment step. Also, verify if the action path should include `/actions/`.

```yaml
    permissions:
      contents: read
      pages: write
      id-token: write
```

## 3. Broken Status Badges in `README.md`

**Cause:** The status badges at the top of `README.md` use relative paths (e.g., `../../workflows/gds/badge.svg`) which do not resolve correctly when viewed on GitHub.
**Recommendation:** Update the badge URLs to use the full GitHub Actions badge URL format:
`https://github.com/<user>/<repo>/actions/workflows/<workflow_file>/badge.svg`

## 4. Potential Incorrect Action Paths

**Cause:** Several workflows (e.g., `docs.yaml`, `gds.yaml`, `fpga.yaml`) use action paths like `TinyTapeout/tt-gds-action/docs@ttihp26a`. In many Tiny Tapeout templates, these sub-actions are located under an `actions/` directory.
**Recommendation:** Verify the correct paths for these actions. If they are failing with "Action not found", they likely need to be updated to:
`TinyTapeout/tt-gds-action/actions/<action_name>@ttihp26a`

## 5. False Positives in `test.yaml`

**Cause:** The step `! grep failure results.xml` in `.github/workflows/test.yaml` can return a success status even if `results.xml` is missing (e.g., if `make` failed to produce it but didn't return a non-zero exit code).
**Recommendation:** Ensure `results.xml` exists before grepping, or rely on `make` exit codes.

```bash
          make
          test -f results.xml
          ! grep failure results.xml
```

## 6. Empty Required Fields in `info.yaml`

**Cause:** The `title`, `author`, and `description` fields in `info.yaml` are empty. This will cause the automated datasheet generation and precheck steps to fail or produce incomplete results.
**Recommendation:** Fill in all required fields in `info.yaml`.

## 7. PDK Paths in `test/Makefile`

**Cause:** The gate-level simulation paths in `test/Makefile` for the IHP SG13G2 PDK might not match the environment provided by the `gl_test` action.
**Recommendation:** Ensure the paths match the IHP PDK structure used by the `tt-gds-action`. Specifically, check if the `ihp-` prefix is required in all directory levels.

## 8. Runner OS Version Risk

**Cause:** All workflows use `runs-on: ubuntu-24.04`. While this is the latest LTS, some EDA tools used in the Tiny Tapeout pipeline (via Docker or otherwise) may have better compatibility with `ubuntu-22.04`.
**Recommendation:** If encountering mysterious tool failures, consider reverting to `ubuntu-22.04`.
