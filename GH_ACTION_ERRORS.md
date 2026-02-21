# Analysis of GitHub Actions Pipeline Errors

This document identifies current errors and risks in the GitHub Actions pipeline for the Tiny Tapeout project and provides recommendations for fixing them.

## 1. Missing Checkout Steps in `gds.yaml`

**Cause:** The `precheck` and `viewer` jobs in `.github/workflows/gds.yaml` did not originally include an `actions/checkout` step. These jobs depend on the presence of project files (like `info.yaml`) to function correctly.
**Status:** Fixed. Checkout steps added.

## 2. Incomplete Documentation Deployment in `docs.yaml`

**Cause:** The `.github/workflows/docs.yaml` workflow was missing the necessary permissions and steps to deploy to GitHub Pages.
**Status:** Fixed. Permissions added. Note: Successful deployment also requires a repository-level setting (see section 9).

## 3. Broken Status Badges in `README.md`

**Cause:** The status badges at the top of `README.md` used relative paths which did not resolve correctly.
**Status:** Fixed. Replaced with absolute GitHub Actions badge URLs.

## 4. Potential Incorrect Action Paths

**Cause:** Some actions were thought to be in sub-directories, but verification shows they are correctly called as `TinyTapeout/tt-gds-action/<action>@ttihp26a`.

## 5. False Positives in `test.yaml`

**Cause:** The step `! grep failure results.xml` in `.github/workflows/test.yaml` could return a success status even if `results.xml` was missing.
**Status:** Fixed. Added `test -f results.xml` to the test step.

## 6. Empty Required Fields in `info.yaml`

**Cause:** The `title`, `author`, and `description` fields in `info.yaml` were empty, causing CI failures.
**Status:** Fixed. Populated with generic placeholders.

## 7. PDK Paths in `test/Makefile`

**Cause:** Potential mismatch in PDK paths for gate-level simulation.
**Recommendation:** Verify paths if gate-level simulations are needed.

## 8. Runner OS Version Risk

**Cause:** `ubuntu-24.04` might have compatibility issues with some older EDA tools.
**Recommendation:** Monitor for mysterious failures and consider `ubuntu-22.04` if necessary.

## 9. GitHub Pages Deployment 404 Error

**Cause:** The `viewer` job may fail with `Error: Failed to create deployment (status: 404)` if GitHub Pages is not enabled for the repository, or the "Source" is not set to "GitHub Actions".
**Recommendation:**
1. Go to the repository **Settings** on GitHub.
2. Select **Pages** in the left sidebar.
3. Under **Build and deployment** > **Source**, ensure that **GitHub Actions** is selected.
4. For more details, see the [Tiny Tapeout FAQ](https://tinytapeout.com/faq/#my-github-action-is-failing-on-the-pages-part).
