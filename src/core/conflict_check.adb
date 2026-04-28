--  Empty body — the package is currently spec-only with a Ghost function.
--  The Is_Safe function is expression-bodied in the spec via its Post,
--  so no body is required for the function itself; this stub exists to
--  keep gprbuild happy when other compilation units `with` this package.

package body Conflict_Check
  with SPARK_Mode => On
is

end Conflict_Check;
