import subprocess

r = subprocess.run(["bash", "-n", "test.sh"], capture_output=True, text=True)
print("exit_code:", r.returncode)
print(r.stderr if r.stderr.strip() else "NO_SYNTAX_ERRORS")
