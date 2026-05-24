{
  description = "gen-scope: demand-driven attribute grammar evaluator over algebraic scope graphs";
  outputs = _: {
    __functor = _: import ./.;
  };
}
