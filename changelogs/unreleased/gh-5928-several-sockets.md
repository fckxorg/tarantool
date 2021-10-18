## feature/core
* Implemented ability to open several listening sockets (up to 20).
  In addition to ability to pass uri as a number or string, as
  previously, ability to pass uri as a table of numbers or strings
  has been added.
  ```lua
  box.cfg { listen = {3301, 3302, 3303} }
  box.cfg { listen = {"127.0.0.1:3301", "127.0.0.1:3302"} }
  ```