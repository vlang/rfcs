# Embedding resources in v programs.

## Motivation (why is this needed):
Programs frequently want to be as standalone as possible, because that
makes distribution to end users much easier. That goal may be achieved by
embedding binary resources directly inside the distributed executable.

## Why existing approaches are not sufficient:

The current ways to embed a binary resource into a V executable are:
1) Add rules to your build system that preprocess binary resources
into .C files suitable for inclusion into your project.

Example using `make`:
```make
0001_embedding_resources.c: 0001_embedding_resources.md
	xxd -i 0001_embedding_resources.md > 0001_embedding_resources.c
```
... then you need to `#include "0001_embedding_resources.c"` in your .v file
The resource will be available to your V program as: 
`C.__0001_embedding_resources_md_len` and `C.__0001_embedding_resources_md`

2) Add rules to postprocess your executable *after it is build* and add:
2.1) data sections containing the binary resources.
2.2) all the resources as a zip file, concatenated after the
executable, which needs to contain a zip extraction code, then open
the executable as a zip archive, etc.

Both of these aproaches have the following pros/cons:
Pros: 
These approaches are language agnostic, and some people already use 
such systems for their existing C projects.

Cons: 
This requires an external build system.
The rules may be platform specific.
The rules need to be written manually.
The v language has no idea about it, so it can not help in any way.
Doing different development vs production builds requires error
prone manual code too.


# Proposed solution: add resource embeding support directly to v itself.

Suppose that you have a v module `abc`, with the following tree structure:
abc/abc.v
abc/resource/table.bin
abc/resource/table.bin_linux
abc/resource/table.bin_windows

Suppose also, that you want to use the module abc in a v program, 
located in a separate folder, with the following structure:
```
project/game.v 
```

Then, in your abc/abc.v file, you can do:
```v
module abc
pub const Table = @embed('resource/table.bin')
```

and in your project/game.v:
```v
import abc
//abc.Table.data() -> will return a byteptr to the embedded binary data
//abc.Table.len  -> will be the size of the uncompressed embedded binary 
                    data block, pointed to by abc.Table.data() .
```

While you develop, the Table.data() method will read the corresponding 
file from the filesystem into a memory buffer and return it.

When you add -prod, the Table.data() method will decompress the stored
data and return a buffer containing the uncompressed version.
The other fields of abc.Table will be initialized in a suitable way too
(similarly to how `xxd -i` produces automatically generated C statics,
which once compiled will embed the data inside the executable).

Embedding will support `_platform` postfix overrides for the files.
The embed_full_path will be assigned and tried the following locations, 
and in this order:
a) *main_path* + *embed_path_platform*
a) *main_path* + *embed_path*
b) *mod_path* + *embed_path_platform*
b) *mod_path* + *embed_path*

In the example from above, the following paths will be tried in order:
1) project/abc/resource/table.bin_linux  ==> missing
2) project/abc/resource/table.bin        ==> missing
3) abc/resource/table.bin_linux          ==> *found* <== 
                                         so this version will be used in the final program
4) abc/resource/table.bin                ==> skipped, because on 3) a more suitable version
                                         of the resource was already found

This search order gives most flexibility, because modules will be free
to provide default versions of resources like fonts or images.

Modules will also be free to provide easily different versions of the
resources for all platforms they wish to support,

The final v user program, that imports the modules with resources, 
will still have the option of overriding some or all of the resources,
if it desires to do so, for example changing module pictures, sounds, fonts,
by just creating the appropriate folder/file, with no code changes to
the modules themselves.


NB: If none of the paths exist, v will produce an informative compile error, 
about which files were tried and found to be missing.


## Implementation details:

The type of abc.Table may be V_Embedded_Data, something like:

```v
pub struct V_Embedded_Data {
  mut:
     try_paths []string
     found_path string
     compressed byteptr
     uncompressed byteptr
  pub:
     len int
}
pub (ved V_Embedded_Data) data() byteptr {
   if !isnil(ved.uncompressed) { return ved.uncompressed }
   // convert from compressed to uncompressed
   // ved.uncompressed := magic
   return ved.uncompressed
}
```

During development, the .data() function will simply (re)read the proper 
binary file into a buffer when the files in ved.try_paths have been changed and return it.
This will allow for tighter integration with external tools like graphics or hex editors.

During production, the .data() function will contain a small and 
fast decompressor for the binary data. Only he most suitable version 
of the binary file will be embedded in the produced executable.

# TODO:

a) How to specify in the @embed() syntax 
different kinds of compressions for different kinds of binary data.

b) Specify live reloading behaviour in relation with changed embed
resources, so that for example texures and sounds could be changed by
an external editor, while a v program is running in development mode
with -live. Not sure if there is a need to do anything special for the
.data() functions, except probably call each of them in a live
reloading hook after a lock is acquired, so that they have a chance to
check their corresponding files for changes and refresh their buffers.

c) Not sure whether the overrides should use postfix `_platform` or
a prefix `platform_` . The prefix version will keep the extension
unchanged, so that external editors and file managers will be able 
to open the platform versions without tweaks, which is a plus.
