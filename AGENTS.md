# Agent Instructions

- Do not create todo or plan files (e.g. `tasks/todo.md`). Track work in the conversation instead.
- Run tests with `swift test`.
- Without Xcode installed, swift-testing's framework is not on the default search
  path, and `swift test` fails to find the `Testing` module. Point it at the
  Command Line Tools copy:

  ```
  FW=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
  LIB=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
  swift test -Xswiftc -F -Xswiftc $FW -Xlinker -F -Xlinker $FW \
    -Xlinker -rpath -Xlinker $FW -Xlinker -rpath -Xlinker $LIB
  ```
