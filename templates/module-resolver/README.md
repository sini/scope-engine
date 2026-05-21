# Module Resolver

LM-style module system with scope graphs, implementing the canonical name resolution example from Neron et al. (2015).

## What it demonstrates

Modules form a scope hierarchy via parent edges (lexical nesting). Imports create cross-scope visibility via import edges. Declarations are resolved through the scope graph using the resolution calculus with specificity ordering D < I < P.

```
module Std {
  module IO     { def print = "io.print"; def format = "io.format" }
  module Math   { def sqrt = "math.sqrt"; def pi = 3 }
  module String { import Math; def concat = "string.concat" }
}
module App {
  import Std.String
  def main = "app.main"
  module Sub {
    import Std.IO
    def helper = "sub.helper"
  }
}
module Cycle1 { import Cycle2 }
module Cycle2 { import Cycle1 }
```

## Features exercised

| Feature | Paper | What it tests |
|---|---|---|
| `query` with specificity | Neron 2015 Fig. 2 | D < I < P ordering: local shadows import shadows parent |
| `transitiveImports` | Neron 2015 §2.5 | App sees Math's `pi` through String's import of Math |
| Seen-imports | Neron 2015 §2.4, rule X | Cycle1 and Cycle2 mutually import without diverging |
| `ambiguous` | van Antwerpen 2018 | Detect when multiple declarations are reachable |
| `shadow` | Neron 2015 §5 Def. 1 | visibleDecls composes local, import, and parent with shadowing |
| `queryAll` | Neron 2015 §2.3 | All reachable declarations in cyclic import scenario |
| `paramAttr` | Sloane 2010 §3 | Parameterized name lookup |
| Structural queries | -- | ancestors, childrenIds, descendants, nodesByType |

## Tests

16 tests covering: direct lookup, import resolution, parent inheritance, transitive imports, non-transitive defaults, ambiguity detection, cyclic import safety, shadowing composition, and structural queries.

```bash
nix eval --override-input scope-engine ../.. .#tests
```

## References

- Neron, Tolmach, Visser, Wachsmuth (2015). "A theory of name resolution." ESOP 2015 -- scope graphs, resolution calculus, seen-imports
- van Antwerpen, Bach Poulsen, Rouvoet, Visser (2018). "Scopes as types." OOPSLA 2018 -- generalized queries, ambiguity
- Sloane, Kats, Visser (2010). "A pure OO embedding of attribute grammars." -- parameterized attributes
