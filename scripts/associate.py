from pathlib import Path

root = Path.home() / "drone-slam/data/rgbd_dataset_freiburg1_desk"

def read_list(filename):
    entries = []
    for line in (root / filename).read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        timestamp, path = line.split()[:2]
        entries.append((float(timestamp), path))
    return entries

rgb = read_list("rgb.txt")
depth = read_list("depth.txt")

# Match each RGB frame to its nearest depth timestamp.
j = 0
pairs = []

for tr, rgb_path in rgb:
    while j + 1 < len(depth) and abs(depth[j + 1][0] - tr) < abs(depth[j][0] - tr):
        j += 1

    td, depth_path = depth[j]
    if abs(tr - td) <= 0.02:
        pairs.append((tr, rgb_path, td, depth_path))

out = root / "associate.txt"
out.write_text("".join(
    f"{tr:.6f} {r} {td:.6f} {d}\n"
    for tr, r, td, d in pairs
))

print(f"RGB frames: {len(rgb)}")
print(f"Depth frames: {len(depth)}")
print(f"Matched pairs: {len(pairs)}")
print(f"Saved: {out}")
