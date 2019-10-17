
In addition to the current cases:

`a := optional() or { panic(err) }`

`a := optional() or { continue }`

`a := optional() or { return }`

and

```
  if val := optional(false) {
     println( val )
  }
```


V should allow also:

`a := optional() or 55`

and

`a := optional() or { log(err) ... 55 }`

