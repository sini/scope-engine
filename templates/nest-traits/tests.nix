{
  lib,
  engine,
  nest,
  schemaLib,
  aspects,
  genLib,
}:
{
  smoke = {
    test-nest-evaluates = {
      expr = nest ? evalNest;
      expected = true;
    };
    test-selectors-exist = {
      expr = nest ? selectors;
      expected = true;
    };
  };
}
