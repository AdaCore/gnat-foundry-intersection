--  Fixture for `tests/test_ada_tracer.py`: one instance of every `--@covers`
--  tag shape the trace chain relies on, plus the untagged constructs that must
--  stay out of the inventory. Parsed by `engine/ada_tracer`, never compiled --
--  keep it legal Ada all the same, and keep the test's expectations in step
--  with the line numbers here.

package Checks is

   T_Sample : constant := 100;
   T_Walk   : constant := 400;

   --  A tagged pragma, written in the multi-line shape `gnatformat` produces
   --  for a long `Compile_Time_Error` (as in `src/types/states.ads`).

   --@covers llr_1_checks.1
   pragma
     Compile_Time_Error
       (T_Walk mod T_Sample /= 0,
        "T_WALK must be an integral multiple of T_SAMPLE (llr_1_checks.1)");

   --  Untagged: a pragma is evidence only when its author opts in.

   pragma Compile_Time_Error (T_Walk > 0, "T_WALK must be positive");

   --  A tag directly above the aspect association, which is how a contract
   --  spanning several lines reads. `SPARK_Mode` opens the list, so the `Post`
   --  is not the first association.

   function Sum (Left, Right : Integer) return Integer
   with
     SPARK_Mode => On,
     --@covers llr_1_checks.2
     Post => Sum'Result = Left + Right;

   --  A tag above the `with` that opens a one-line aspect list -- the only way
   --  to annotate `with Post => ...` (as in `src/core/controller.ads`).

   function Product (Left, Right : Integer) return Integer
            --@covers llr_1_checks.3
   with Post => Product'Result = Left * Right;

   --  Two ids on one tag line, and a second tag line on the same construct:
   --  the payloads are reported in source order and the consumer unions them.

   function Negate (Value : Integer) return Integer
   with
     --@covers llr_1_checks.4, llr_1_checks.5
     --@covers llr_1_checks.6
     Post => Negate'Result = -Value;

   --  A compiler-checked aspect rather than a contract: the `STATIC` layer's
   --  other anchor (as in `src/core/state_machine_loop.ads`).

   procedure Halt
   with
     SPARK_Mode => On,
     --@covers llr_1_checks.7
     No_Return;

   --  Tagged `none`: a check guarding something no requirement governs.

   function Bounded (Value : Integer) return Integer
   with
     --@covers none: guards an implementation detail
     Pre => Value < 100;

   --  A broken tag: the payload names nothing. Reported as a check all the
   --  same, so the trace engine can diagnose it (E-TRACE-CHECK-EMPTY) rather
   --  than lose it -- and on a `Pre`, which no layer's anchors accept.

   function Broken (Value : Integer) return Integer
   with
     --@covers
     Pre => Value > 0;

   --  Untagged contracts, the common case: most exist for proof plumbing and
   --  cite nothing.

   function Doubled (Value : Integer) return Integer
   with Post => Doubled'Result = 2 * Value;

end Checks;
