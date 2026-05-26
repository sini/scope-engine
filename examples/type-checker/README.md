# Type Checker

Structural record types and class inheritance via scope graphs, implementing the motivating example from van Antwerpen et al. (2018).

## What it demonstrates

Record types are modeled as scopes with field declarations. Record extension uses R (record) edges. Class inheritance uses E (extension) edges. Structural subtyping checks that one scope's fields are a subset of another's. HOAG synthesis instantiates generic types.

```
type Point2D = { x: Num, y: Num }
type Point3D = { x: Num, y: Num, z: Num }
type NamedPoint = { name: String } extends Point2D
type Pair<A,B> = { fst: A, snd: B }                -- generic, HOAG-synthesized

class Shape     { area: () -> Num }
class Circle    extends Shape { radius: Num }
class Rect      extends Shape { width: Num, height: Num }

distance(p3, origin)  -- OK: Point3D <: Point2D
```

## Features exercised

| Feature | Paper | What it tests |
|---|---|---|
| `subtypeOf` | van Antwerpen 2018 §2.3 | Point2D <: Point3D, structural field subset check |
| Custom edge labels (R, E) | van Antwerpen 2018 §2.1 | Record extension and class inheritance as labeled edges |
| `followEdge` / `collectByLabel` | van Antwerpen 2018 §2.1 | Traverse custom edges for field collection |
| Scoped relations | van Antwerpen 2018 §2.1 | Separate type vs value namespaces via `rels` |
| HOAG synthesis | Vogt 1989 | Instantiate Pair\<Num, String\> via `synthesize` |
| `nodesByType` | -- | Find all record types including synthesized ones |
| `ambiguous` | van Antwerpen 2018 | Detect field name ambiguity in extension chains |

## Tests

23 tests covering: structural subtyping (positive/negative), record field extension via R edges, class inheritance via E edges, scoped type/value namespaces, HOAG generic instantiation, typed queries, and ambiguity detection.

```bash
nix eval --override-input scope-engine ../.. .#tests
```

## References

- van Antwerpen, Bach Poulsen, Rouvoet, Visser (2018). "Scopes as types." OOPSLA 2018 -- structural records, subtyping, custom edge labels, scoped relations
- Neron, Tolmach, Visser, Wachsmuth (2015). "A theory of name resolution." ESOP 2015 -- class inheritance as import edges (§3, Fig. 16)
- Vogt, Swierstra, Kuiper (1989). "Higher-order attribute grammars." -- dynamic node synthesis
