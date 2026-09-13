# Working on Workbench

Read [the product contract](docs/workbench.md), [the source map](docs/design.md) and [CONTRIBUTING](CONTRIBUTING.md) before changing behavior. Inspect current source and release state; an illustration, passing build or another agent's answer is not proof of a working feature.

For wallpaper and presentation, [the structured experience contract](site/handbook/contract.json) owns capability status, lifecycle and acceptance scenarios. The website generates its human and agent records from it. Update that record when the implemented contract changes; use GitHub issues for agreed work rather than creating another backlog.

Choose one user outcome, its state owner and a bounded change. Preserve originals, later manual desktop choices and independent jobs. Validate with synthetic data and report the tests actually run, screenshots, source revision and hardware/receiver limits. Do not replace live user data for tests.

Keep private records and credentials out of code, images and public evidence. Do not read or publish `site/.env.local`. Apple submission, notarization, public binary publication and external communications require their applicable task authority; documentation does not grant it.
