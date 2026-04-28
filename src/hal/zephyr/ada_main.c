/*
 * ada_main.c — Zephyr C entry point for the Ada/SPARK application.
 *
 * adainit() runs Ada package elaboration; _ada_main() is GNAT's symbol
 * for the top-level `procedure Main` in src/app/main.adb. The Ada main
 * loop never returns, so the trailing spin is defensive.
 */
extern void adainit(void);
extern void _ada_main(void);

int main(void)
{
	adainit();
	_ada_main();
	for (;;) { }
}
