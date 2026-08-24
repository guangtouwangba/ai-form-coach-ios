# Contributing

Thanks for helping improve AI Form Coach. This is an early-stage fitness
assistance prototype, so changes that affect exercise judgement need stronger
evidence than ordinary UI changes.

## Local workflow

1. Create a focused branch from `main`.
2. Add or update deterministic `FormCoachCore` tests first.
3. Run `./Scripts/verify.sh`.
4. Open a pull request explaining user impact, test evidence and any changed
   thresholds or model versions.

## Exercise-rule changes

- Do not present rules as medical diagnosis or injury prevention.
- Include the affected exercise phase, threshold, confidence behavior and
  expected false-positive trade-off.
- Avoid tuning against a single athlete. Validation data must be split by
  person, not by video clip.
- Never commit identifiable workout videos without documented consent and an
  appropriate data-use agreement.

## Code style

Prefer small, testable domain types. Keep camera/model adapters outside
`FormCoachCore`, preserve frame ordering, and make uncertainty explicit rather
than guessing through missing landmarks.
