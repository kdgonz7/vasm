# Guidelines for the VASM codebase

* Never panic! There is (most of the time) a better way to do an action that doesn't require a panic and sudden program shutdown.
* Always prioritize safety over speed. VOLT is about building reliable compilers and software.
* Write code where no bugs can lay in. Use RAID.
* Always write at least 5 tests before even thinking of publishing code
* Always have a free function (`deinit`) even if there's no point in freeing
* Make intentions clear
* Always have a location for an error.
* Encourage proper styles!
* It's usually better to infer. Dynamic syntax is almost always a better look
