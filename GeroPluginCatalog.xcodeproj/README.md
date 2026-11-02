# Xcode project generation

The project specification is maintained in `project.yml` and uses XcodeGen.
Install XcodeGen (for example with Homebrew: `brew install xcodegen`), then run:

```sh
xcodegen generate
open GeroPluginCatalog.xcodeproj
```

This keeps the project definition readable and makes the generated Xcode project reproducible.
