# Stable upstream synchronization for the SSH fork

The fork maintains SSH product changes on `feat/ssh-settings-ux`. The `main` branch hosts the
synchronization controller so GitHub can schedule it; a controller merge does not install or
release the SSH app. `SSH_PRODUCT_BRANCH` may select another existing product branch later.

`Sync official stable release` runs daily at about 09:23 Asia/Taipei and supports manual dispatch.
GitHub schedules can be delayed. It reads official stable release tags only, never daily upstream
main or beta tags. No new release, or an already-integrated tag, produces no product change.

A new tag is merged on an isolated `feat/ssh-upstream-vX.Y.Z` branch. SSH changes remain in the
merge history. Any conflict fails before pushing; no automatic conflict strategy or force push is
used. It creates a review-only PR and explicitly dispatches `remote-usage-build.yml` for that ref.
GitHub suppresses normal push/PR workflow triggers from GITHUB_TOKEN, so this dispatch is required.
The CI runs the Python exporter tests, complete Swift tests and App bundle build. Review its exact
head SHA and result, plus relevant SSH/account-history/GUI behavior, before merging.

Only same-repository PRs are reused; a different fork with the same branch name is ignored.
An explicitly closed/merged sync PR is not recreated for the same tag; reopen it or choose a newer
release if that decision changes. An existing open PR is reused; CI is dispatched only when that exact head has no existing run. If a
push succeeded but PR creation failed, an equivalent orphan branch may be reused without a force
push. A differing branch is left for human review. An existing failing CI is not automatically
re-run or merged: fix/review the failure first.

## Activation

1. Merge the controller PR into the fork's default `main` branch.
2. The repository setting "Allow GitHub Actions to create and approve pull requests" must permit
   PR creation. GitHub combines creation and approval in one setting; this controller never
   approves, auto-merges, tags or releases anything. The repository currently disables this setting.
3. Keep contents/pull-requests/actions write permissions limited to the synchronization job. The
   test job has read-only contents access; pull-request events never run the publication job.
4. Manually dispatch once, confirm the existing official sync PR is reused, and confirm the
   corresponding CI checks exist. Then leave the daily schedule active.

No personal access token, private signing key or user SSH credential is stored by this controller.
App auto-update is a separate release task requiring a fork-owned update feed, signing setup,
version policy and a tested old-to-new installation path. This controller alone does not enable
Sparkle or replace an installed app.

The first official integration PR is https://github.com/livejiaquan/openusage/pull/2 .
