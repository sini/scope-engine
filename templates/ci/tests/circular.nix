{ lib, engine, ... }:
{
  circular = {
    test-converges = {
      expr =
        let
          baseNodes = engine.buildNodes {
            parentGraph = engine.vertex "x";
            decls = {
              x = {
                target = 5;
              };
            };
          };
          result = engine.eval {
            inherit baseNodes;
            attributes = {
              # Converge: start from 0, add 1 each iteration until hitting target.
              count = engine.circular { init = 0; } (
                self: id: prev:
                let
                  target = self.nodes.${id}.decls.target;
                in
                if prev >= target then prev else prev + 1
              );
            };
          };
        in
        result.evaluated.x.get "count";
      expected = 5;
    };

    test-divergence-throws = {
      expr =
        let
          baseNodes = engine.buildNodes {
            parentGraph = engine.vertex "x";
          };
          result = engine.eval {
            inherit baseNodes;
            attributes = {
              diverge = engine.circular {
                init = 0;
                maxIter = 5;
              } (_self: _id: prev: prev + 1);
            };
          };
          tried = builtins.tryEval (result.evaluated.x.get "diverge");
        in
        tried.success;
      expected = false;
    };
  };
}
