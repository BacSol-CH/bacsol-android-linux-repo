# Recipe for the Termux-style build of this package.
# Source snapshot: ./src (canonical source of this package).
# Upstream tarball pin + sha256: see UPSTREAM.md.
# $WORKDIR is the recipe build directory provided by the termux-build tooling.
TERMUX_PKG_HOMEPAGE=https://github.com/storytold/gridcraft
TERMUX_PKG_DESCRIPTION="Craft app (Termux/X11 build, no APK path)"
TERMUX_PKG_LICENSE="MIT"
TERMUX_PKG_MAINTAINER="BacSol"
TERMUX_PKG_VERSION=0.17.0
TERMUX_PKG_SRCURL="https://github.com/storytold/gridcraft/archive/refs/tags/v${TERMUX_PKG_VERSION}.tar.gz"
TERMUX_PKG_SHA256=eabb7f383f45b98d852b5a4787ff16a6\
fcbaca3dd1aaf9213a69de78f14fdc75  # leakscan-ok: upstream tarball sha256 integrity pin (public)
TERMUX_PKG_DEPENDS="fontconfig, freetype, libxcursor, libxi, libxrandr, libxkbcommon"
TERMUX_PKG_BUILD_DEPENDS="libxcb, ncurses"
TERMUX_PKG_BUILD_IN_SRC=true
TERMUX_GLIBC_BUFFER_WORKAROUND=true

termux_step_post_get_source() {
	# x11-only: drop wayland feature strings before resolution touches them
	sed -i 's/, "wayland"//; s/, "wayland-csd-adwaita-notitle"//; s/, "wayland-data-control"//' \
		apps/*/Cargo.toml crates/*/Cargo.toml Cargo.toml 2>/dev/null || true
	# the egui fork rev carries no egui_demo_lib/apps package -> cargo hard-errors on
	# those patch entries; strip from manifests and .cargo/config.toml alike
	sed -i 's|^rfd = "0.17"|rfd = { version = "0.17", default-features = false, features = ["xdg-portal"] }|' Cargo.toml
	sed -i '/^egui_demo_lib = /d; /^egui_inspection = /d; /^egui_system_font_provider = /d' Cargo.toml
	if [ -f .cargo/config.toml ]; then
		python - <<'PYEOF'
import re
p = '.cargo/config.toml'
s = open(p).read()
# drop any [patch.<...>] tables pointing at the egui git fork
s = re.sub(r'\[patch\.[^\]]*storytold/egui[^\]]*\]\n(?:[^\[]|\[[^\]]*\][^\n]*\n(?!\[))*', '', s)
open(p, 'w').write(s)
PYEOF
	fi
}

termux_step_configure() {
	termux_setup_cmake
	termux_setup_rust
	cargo clean
	# repo config redirects sources to its shipped vendor/ dir, which breaks cargo vendor
	# itself (missing .cargo-checksum.json on hayro); sanitize before vendoring
	rm -f .cargo/config.toml
	cargo vendor > vendor-config.raw
	sed -e 's|\$CARGO_TARGET_DIR|target/|' -e 's|../vendor|./vendor|g' vendor-config.raw > vendor-config.toml

	mkdir -p .cargo
	cp vendor-config.toml .cargo/config.toml

	local crate patch_lines=""
	for crate in arboard rfd winit glutin glutin_glx_sys smithay-client-toolkit wayland-cursor x11rb-protocol xkbcommon-dl egui-winit eframe; do
		[ -d "vendor/$crate" ] || continue
		for vdir in "vendor/$crate" vendor/"$crate"-*; do
			[ -d "$vdir" ] || continue
			if [ "$crate" = "smithay-client-toolkit" ] || [ "$crate" = "wayland-cursor" ]; then
				python3 - "$vdir" <<'SRMEOF'
import os, re, sys
d = sys.argv[1]
imported = re.compile(r"^\s+shm::\{[^}]*\},\n", re.M)
for root, _, fs in os.walk(d):
    for f in fs:
        if not f.endswith(".rs"):
            continue
        p = os.path.join(root, f)
        s = open(p).read()
        if "rustix::shm" not in s and not imported.search(s):
            continue
        o = s
        s = imported.sub("", s)
        # single-name import inside braced use rustix block: shm::Mode / shm::OFlags
        s = re.sub(r"^\s+shm::[A-Za-z_]+,\n", "", s, flags=re.M)
        s = s.replace("use rustix::shm;\n", "")
        if s == o:
            print("WARN: no import removed in", p)
        s = s.replace("Err(Errno::NOSYS) => (),", "Err(Errno::NOSYS) => return Err(Errno::NOSYS.into()),")
        s = s.replace("Err(Errno::NOSYS) => break,", "Err(Errno::NOSYS) => return Err(Errno::NOSYS.into()),")
        m = re.search(r"(?m)^(?: {4,8}// Fallback to using shm_open| {4,8}let (?:time|sys_time) = SystemTime::now\(\);)", s)
        if not m:
            continue
        a = s.rfind("\nfn ", 0, m.start())
        b = s.rfind("\n    fn ", 0, m.start())
        fn_i = max(a, b)
        fn_indent = 0 if a > b else 4
        start = s.rindex("\n", 0, m.start())
        close_pat = "\n" + " " * fn_indent + "}\n"
        end = s.index(close_pat, m.start())
        s = s[:start] + "\n" + " " * (fn_indent + 4) + "unreachable!()" + s[end:]
        open(p, "w").write(s)
        print("excised rustix::shm fallback:", p)
SRMEOF
			fi
			# Termux alacritty recipe: neutralize android cfgs BEFORE promoting linux cfgs,
			# so winit's android-activity dep never enters the graph (featureless -> compile_error)
			find "$vdir" -type f -print0 | xargs -0 sed -i \
				-e 's|"android"|"disabling_this_because_it_is_for_building_an_apk"|g' \
				-e 's|"linux"|"android"|g' \
				-e 's|libxkbcommon.so.0|libxkbcommon.so|g' \
				-e 's|libxkbcommon-x11.so.0|libxkbcommon-x11.so|g' \
				-e 's|libxcb.so.1|libxcb.so|g' \
				-e "s|/tmp|$TERMUX_PREFIX/tmp|g"
			done
		case "$crate" in
			egui|egui-winit|eframe|winit)
				# already patched to the fork git source by the repo manifest; sed edits
				# apply directly because cargo vendor replaced that git source with ./vendor
				continue
				;;
		esac
		patch_lines="${patch_lines}${crate} = { path = \"./vendor/${crate}\" }"$'\n'
	done

	# refresh .cargo-checksum.json for every vendored dir we rewrote, so cargo
	# directory-source verification passes on unpatched multi-version duplicates
	for vdir in vendor/*/; do
		vdir="${vdir%/}"
		[ -f "$vdir/.cargo-checksum.json" ] || continue
		python3 - "$vdir" <<'CKEOF'
import os, json, sys, hashlib
d = sys.argv[1]
ckp = os.path.join(d, ".cargo-checksum.json")
ck = json.load(open(ckp))
files = {}
for root, _, fs in os.walk(d):
    for f in fs:
        if f == ".cargo-checksum.json":
            continue
        rel = os.path.relpath(os.path.join(root, f), d)
        files[rel] = hashlib.sha256(open(os.path.join(root, f), "rb").read()).hexdigest()
ck["files"] = files
json.dump(ck, open(ckp, "w"))
CKEOF
	done

	if [ -n "$patch_lines" ]; then
		if grep -q '^\[patch\.crates-io\]' Cargo.toml; then
			awk -v add="$patch_lines" '/^\[patch\.crates-io\]$/{print; printf "%s", add; next} {print}' Cargo.toml > Cargo.toml.new && mv Cargo.toml.new Cargo.toml
		else
			printf '\n[patch.crates-io]\n%s' "$patch_lines" >> Cargo.toml
		fi
	fi
}

termux_step_make() {
	cargo build -j20 --release --target "$CARGO_TARGET_NAME" --offline
}

termux_step_make_install() {
	for bin in gridcraft; do
		install -Dm700 -t "$TERMUX_PREFIX/bin" "target/$CARGO_TARGET_NAME/release/$bin" || true
	done
}
