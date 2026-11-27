#!/usr/bin/env python3
"""
وضعیت ماشین: «چی روی لینوکس تغییر کرده؟»
  start   : اول شیفت (قبل از هر restore) — لیست پکیج‌ها و یک marker زمانی ثبت میشه
  prepare : آخر شیفت — پکیج‌های نصب‌شده + فایل‌های تغییرکرده رو حساب می‌کنه (تجمعی نسبت به شیفت‌های قبل)
باید با root اجرا بشه:  sudo env RUNNER_HOME="$HOME" python3 runner/state.py <cmd>
"""
import glob, os, re, subprocess, sys

HOME = os.environ.get("RUNNER_HOME") or os.path.expanduser("~")
os.environ["RUNNER_HOME"] = HOME
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
START_DIR, STATE_DIR = "/var/tmp/runner-start", "/var/tmp/runner-state"
SKIP_PKG = ("linux-image", "linux-headers", "linux-modules", "linux-tools", "linux-azure")


def out(args):
    return subprocess.run(args, capture_output=True, text=True).stdout


def installed():
    return {l for l in out(["dpkg-query", "-W", "-f=${binary:Package}\n"]).split("\n") if l}


def lines(path, comments=True):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            ls = [l.rstrip("\n") for l in f]
    except FileNotFoundError:
        return []
    ls = [l for l in ls if l.strip()]
    return [l for l in ls if not l.lstrip().startswith("#")] if comments else ls


def write(path, items):
    with open(path, "w", encoding="utf-8") as f:
        f.write("".join(i + "\n" for i in items))


def expand(p):
    p = re.sub(r"\s+#.*$", "", p).strip()
    if p.startswith("~"):
        p = HOME + p[1:]
    return os.path.expandvars(p)


def repo_packages(names):
    """پکیج‌هایی که از ریپوی apt قابل نصب‌اند (نه .deb دستی)"""
    names, repo = sorted(names), set()
    for i in range(0, len(names), 200):
        cur = None
        for line in out(["apt-cache", "policy", *names[i:i + 200]]).splitlines():
            m = re.match(r"^(\S+):\s*$", line)
            if m:
                cur = m.group(1)
            elif cur and re.search(r"https?://", line):
                repo.add(cur)
    return repo


def owned_files(pkgs):
    s = set()
    for p in pkgs:
        for f in [f"/var/lib/dpkg/info/{p}.list"] + glob.glob(f"/var/lib/dpkg/info/{p}:*.list"):
            try:
                s.update(l.rstrip("\n") for l in open(f, encoding="utf-8", errors="replace"))
            except OSError:
                pass
    return s


def cmd_start():
    os.makedirs(START_DIR, exist_ok=True)
    write(f"{START_DIR}/installed.start", sorted(installed()))
    open(f"{START_DIR}/marker", "w").close()
    print(f"baseline saved ({len(installed())} packages)")


def cmd_prepare(listfile):
    marker = f"{START_DIR}/marker"
    if not os.path.exists(marker):
        print("❌ marker وجود نداره (state.py start اجرا نشده)"); return 1
    mt = os.stat(marker).st_mtime
    os.makedirs(STATE_DIR, exist_ok=True)

    # ── پکیج‌ها (تجمعی) ──
    now = installed()
    new = {p for p in now - set(lines(f"{START_DIR}/installed.start", False)) if not p.startswith(SKIP_PKG)}
    allp = set(lines(f"{STATE_DIR}/pkgs.all", False)) | new
    present = allp & now
    ok = subprocess.run(["apt-get", "update", "-qq"], capture_output=True).returncode == 0
    if not ok:
        print("⚠️ apt-get update ناموفق بود — همه‌ی پکیج‌ها ریپویی فرض شدن")
    repo = repo_packages(present) if ok else set(present)
    local_prev = set(lines(f"{STATE_DIR}/pkgs.local", False))   # .deb های دستیِ شیفت‌های قبل (dpkg روی این ماشین نمی‌شناسدشون)
    local = (present - repo) | local_prev
    write(f"{STATE_DIR}/pkgs.all", sorted(allp))
    write(f"{STATE_DIR}/pkgs.repo", sorted(((allp - present) | repo) - local_prev))
    write(f"{STATE_DIR}/pkgs.local", sorted(local))
    print(f"📦 پکیج‌ها: {len(repo)} از ریپو، {len(local)} نصب دستی (.deb) — فایل‌های اون‌ها مستقیم داخل بکاپ میره")

    # ── فایل‌های تغییرکرده ──
    roots = [expand(l) for l in lines(f"{ROOT}/overlay.roots")]
    excl = [re.compile(l.replace("{HOME}", re.escape(HOME))) for l in lines(f"{ROOT}/overlay.exclude")]
    skip = lambda p: any(r.search(p) for r in excl)
    owned = owned_files(repo)
    # فایل‌های پکیج‌های .deb دستی: خارج از roots هم باید بره (مثلاً /usr/lib/code-server)
    local_files = {f for f in owned_files(present - repo)
                   if (os.path.islink(f) or os.path.isfile(f)) and not skip(f)}
    changed = set()
    for root in roots:
        if not os.path.isdir(root):
            continue
        dev = os.lstat(root).st_dev
        for dp, dns, fns in os.walk(root, followlinks=False):
            keep = []
            for d in dns:
                p = os.path.join(dp, d)
                try:
                    if skip(p) or os.lstat(p).st_dev != dev: continue
                except OSError:
                    continue
                keep.append(d)
            dns[:] = keep
            for n in keep + fns:
                p = os.path.join(dp, n)
                try:
                    if os.lstat(p).st_mtime > mt and not skip(p):
                        changed.add(p)
                except OSError:
                    pass
    prev = {p for p in lines(f"{STATE_DIR}/overlay.manifest", False) if os.path.lexists(p) and not skip(p)}
    final = sorted((changed | prev | local_files) - owned)
    write(f"{STATE_DIR}/overlay.manifest", final)
    with open(listfile, "wb") as f:
        for p in final:
            f.write(p.lstrip("/").encode("utf-8", "surrogateescape") + b"\0")
    print(f"🗂️ فایل‌ها: {len(changed)} تغییر جدید + {len(prev)} از شیفت‌های قبل = {len(final)} مورد")
    return 0


if __name__ == "__main__":
    c = sys.argv[1] if len(sys.argv) > 1 else ""
    if c == "start": cmd_start()
    elif c == "prepare" and len(sys.argv) > 2: sys.exit(cmd_prepare(sys.argv[2]))
    else: print(__doc__); sys.exit(2)
