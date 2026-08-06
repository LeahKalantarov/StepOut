from checker.step_checker import check_steps

WRONG_STEPS = ["2x + 5 = 13", "2x = 8", "x = 5"]
CORRECT_STEPS = ["2x + 5 = 13", "2x = 8", "x = 4"]
WRONG_ANSWER = ["2x = 8", "x = 6"]
WRONG_DIVISOR = ["3x = 18", "x = 6"]  # if mis-stepped via /3 on wrong problem


def run_test(title, steps):
    print(f"=== {title} ===")

    result = check_steps(steps)

    # Step 1 is always OK — it's the problem statement
    print("Step 1: OK")

    for i in range(1, len(steps)):
        step_number = i + 1

        if not result["ok"] and result["error_step"] == step_number:
            print(f"Step {step_number}: ERROR — {result['message']}")
            if result.get("reason"):
                print(f"           reason={result['reason']}")
            break

        print(f"Step {step_number}: OK")

    print()


if __name__ == "__main__":
    run_test("Wrong solution", WRONG_STEPS)
    run_test("Correct solution", CORRECT_STEPS)
    run_test("Wrong final answer", WRONG_ANSWER)
    run_test("3x=18 then x=6 (should pass)", WRONG_DIVISOR)
