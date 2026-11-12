from pathlib import Path
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

D = Path.home() / "drone-slam/results/live_gazebo"
SLAM_FILE = D / "LiveCameraTrajectory.txt"
GT_FILE = D / "ground_truth.txt"

def load_tum(path):
    rows = []
    with path.open() as f:
        for line in f:
            fields = line.split()
            if len(fields) < 8:
                continue
            try:
                row = [float(v) for v in fields[:8]]
                if np.all(np.isfinite(row)):
                    rows.append(row)
            except ValueError:
                continue
    if not rows:
        raise ValueError(f"No valid TUM trajectory rows in {path}")
    return np.asarray(rows, dtype=float)

gt = load_tum(GT_FILE)
est = load_tum(SLAM_FILE)

gt = gt[np.argsort(gt[:, 0])]
est = est[np.argsort(est[:, 0])]

# Remove duplicate ground-truth timestamps for interpolation.
_, unique_idx = np.unique(gt[:, 0], return_index=True)
gt = gt[np.sort(unique_idx)]

# Keep only SLAM poses inside the ground-truth time interval.
mask = (est[:, 0] >= gt[0, 0]) & (est[:, 0] <= gt[-1, 0])
matched_est = est[mask]

if len(matched_est) < 10:
    raise RuntimeError(
        f"Only {len(matched_est)} overlapping SLAM poses. "
        "Check timestamps and recorder files before evaluating."
    )

t = matched_est[:, 0]
X = matched_est[:, 1:4]  # SLAM camera positions

# Interpolate Gazebo ground truth at each SLAM timestamp.
Y = np.column_stack([
    np.interp(t, gt[:, 0], gt[:, axis])
    for axis in (1, 2, 3)
])

# Estimate similarity transform: Gazebo ~= scale * R * SLAM + translation.
mx, my = X.mean(axis=0), Y.mean(axis=0)
Xc, Yc = X - mx, Y - my

variance = np.mean(np.sum(Xc * Xc, axis=1))
if variance < 1e-12:
    raise RuntimeError("SLAM trajectory has insufficient positional variation.")

U, singular_values, Vt = np.linalg.svd(Yc.T @ Xc / len(X))
correction = np.eye(3)
if np.linalg.det(U @ Vt) < 0:
    correction[2, 2] = -1

R = U @ correction @ Vt
scale = np.sum(singular_values * np.diag(correction)) / variance
X_aligned = scale * (Xc @ R.T) + my

errors = np.linalg.norm(X_aligned - Y, axis=1)
rmse = np.sqrt(np.mean(errors ** 2))
median = np.median(errors)
maximum = np.max(errors)

def path_length(P):
    return float(np.sum(np.linalg.norm(np.diff(P, axis=0), axis=1)))

gt_path = path_length(Y)
aligned_path = path_length(X_aligned)
gt_net = float(np.linalg.norm(Y[-1] - Y[0]))
slam_raw_net = float(np.linalg.norm(X[-1] - X[0]))

# Write aligned pointwise data.
csv_file = D / "live_aligned_trajectory.csv"
np.savetxt(
    csv_file,
    np.column_stack((t, Y, X_aligned, errors)),
    delimiter=",",
    header="timestamp,gt_x,gt_y,gt_z,slam_aligned_x,slam_aligned_y,"
           "slam_aligned_z,position_error_m",
    comments=""
)

# XY trajectory comparison.
fig, ax = plt.subplots(figsize=(9, 7))
ax.plot(Y[:, 0], Y[:, 1], label="Gazebo ground truth")
ax.plot(X_aligned[:, 0], X_aligned[:, 1],
        label="ORB-SLAM3 aligned and scale-corrected")
ax.scatter(Y[0, 0], Y[0, 1], marker="o", label="Start")
ax.scatter(Y[-1, 0], Y[-1, 1], marker="x", label="End")
ax.set_xlabel("X (m)")
ax.set_ylabel("Y (m)")
ax.set_title("Live Gazebo vs ORB-SLAM3 trajectory")
ax.axis("equal")
ax.grid(True)
ax.legend()
fig.tight_layout()
fig.savefig(D / "live_trajectory_comparison.png", dpi=160)
plt.close(fig)

# Aligned position error over time.
fig, ax = plt.subplots(figsize=(10, 4))
ax.plot(t, errors)
ax.set_xlabel("Gazebo simulation time (s)")
ax.set_ylabel("Aligned position error (m)")
ax.set_title("Live trajectory error after similarity alignment")
ax.grid(True)
fig.tight_layout()
fig.savefig(D / "live_trajectory_error.png", dpi=160)
plt.close(fig)

metrics = [
    "LIVE GAZEBO SLAM EVALUATION",
    "Metric: position ATE after similarity alignment and scale correction",
    f"SLAM input rows: {len(est)}",
    f"Ground-truth input rows: {len(gt)}",
    f"Timestamp-matched SLAM poses: {len(X)}",
    f"Overlapping interval: {t[0]:.3f} to {t[-1]:.3f} s",
    f"Estimated scale: {scale:.6f} metres per SLAM map unit",
    f"Aligned ATE RMSE: {rmse:.6f} m",
    f"Aligned ATE median: {median:.6f} m",
    f"Aligned ATE maximum: {maximum:.6f} m",
    f"Ground-truth path length: {gt_path:.6f} m",
    f"Aligned SLAM path length: {aligned_path:.6f} m",
    f"Ground-truth net displacement: {gt_net:.6f} m",
    f"Raw SLAM net displacement: {slam_raw_net:.6f} map units",
    "",
    "Caution: monocular scale and coordinate alignment were estimated from",
    "the same trajectory. Report this as aligned ATE, not independent metric",
    "accuracy. The SLAM pose is the camera pose; ground truth is the drone",
    "model pose, so camera-to-body extrinsics may affect the comparison."
]

report = "\n".join(metrics) + "\n"
(D / "live_evaluation_metrics.txt").write_text(report)
print(report)
print("Saved:")
print(D / "live_trajectory_comparison.png")
print(D / "live_trajectory_error.png")
print(csv_file)
