import subprocess, time, statistics, os
env_path = os.environ["LUA_PATH"]
cases = [("bare", ["-e", "local x=1"], env_path), ("dev", ["run_dev.lua", "-n", "3", "Ada"], env_path),
         ("built", ["run_built.lua", "-n", "3", "Ada"], env_path),
         ("bundle", ["run_bundle.lua", "-n", "3", "Ada"], "/nonexistent/?.lua")]
for interp in ["lua", "luajit"]:
    s = {c[0]: [] for c in cases}
    for _ in range(150):
        for name, args, lp in cases:
            t = time.perf_counter()
            subprocess.run([interp] + args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env={**os.environ, "LUA_PATH": lp})
            s[name].append((time.perf_counter() - t) * 1000)
    m = {n: statistics.median(v) for n, v in s.items()}
    print(interp.ljust(7), " | ".join(f"{n} {m[n]:5.1f} ms (+{m[n]-m['bare']:.1f})" for n in m))
