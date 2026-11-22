# Version and build numbers

The marketing version identifies the release. The build number identifies a
specific package and must increase over time. Give every newly packaged code
revision a fresh build number, even before phone testing. A retry from the exact
same source and candidate may keep its number.

Simulator results do not prove that an IPA works on a phone. For an official
release, the machine-readable marker (for example `<!-- elsepin-build: 93 -->`),
the visible `Build 93`, and the actual IPA must agree. Offer an update for the
same marketing version only when both build numbers are known and the official
one is higher. If either build is unknown, do not guess.

Use `project.yml` for both app and extension build numbers. Regenerate the Xcode
project before compiling. Record the source commit and CI run in BUILD-HISTORY.
Read the finished IPA's Info.plist before delivery. Publication remains a
separate owner-authorized step; build 93 is a test candidate, not a public release.
