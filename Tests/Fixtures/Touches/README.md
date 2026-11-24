# Recorded touch fixtures

Real trackpad gestures, recorded with `swift Scripts/record-touches.swift` and
replayed through `ThreeFingerSwipeRecognizer` by `TouchReplayTests`. Each
`<scenario>.json` holds every frame of one gesture: time since the first touch,
and each finger's id, state (4 = touching) and normalized position.

To record or re-record, on a Mac from the repo root with Grindow quit:

```sh
swift Scripts/record-touches.swift                  # every scenario
swift Scripts/record-touches.swift four-lift-early  # just one
```

Expected outcomes live in `TouchReplayTests.expectations`. A new scenario needs
an entry there and in the script's scenario list.
