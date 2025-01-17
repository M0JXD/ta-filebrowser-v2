# ta-filebrowser-v2
Mitchell's Textadept file_browser module with some additions.

## About

This is mostly the same as the [original version](https://github.com/orbitalquark/textadept/wiki/ta-filebrowser) but adds some sorting options that refugees from other editors may find helpful.

1) The highlighting is fixed for Textadept 12 and now uses multiple colours depending on expanded/folded state.
2) There are simple booleans that can be set to hide dot files/folders, sort without case sensitivity and force the folders to be listed first.

## Installation

Add this module's init.lua under the "file_browser" folder the same way as is detailed in the textadept wiki.

You can then initialise it in your textadept's init.lua. Here's an example:

```
-- File Browser Module
local file_browser = require('file_browser')
keys['ctrl+O'] = file_browser.init
table.insert(textadept.menu.menubar[_L['File']], 3, {
    'Open Directory...', file_browser.init
})
file_browser.hide_dot_folders = true
file_browser.hide_dot_files = false
file_browser.force_folders_first = true
file_browser.case_insensitive_sort = true
```

## Colour Customisation

The colours depend on keywords defined by Textadept's [lexer tags](https://orbitalquark.github.io/textadept/api.html#lexer).
You can modify them in the "highlight_folder" function.

