from pathlib import Path
import numpy as np
import matplotlib.pyplot as plt

ROOT = Path.home() / "drone-slam"
DATA = ROOT / "data/rgbd_dataset_freiburg1_desk"
RESULTS = ROOT / "results"

est_file = RESULTS / "CameraTrajectory.txt"
gt_file = DATA / "groundtruth.txt"

# TUM trajectory format:
# timestamp tx ty tz qx qy qz qw
est = np.loadtxt(est_file)
gt = np.loadtxt(gt_file, comments="#")

# Match every estimated pose to the nearest ground-truth timestamp.
gt_times = gt[:, 0]
est_times = est[:, 0]
indices = np.searchsorted(gt_times, est_times)

indices = np.clip(indices, 0, len(gt_times) - 1)
previous = np.clip(indices - 1, 0, len(gt_times) - 1)

use_previous = (
    np.abs(gt_times[previous] - est_times)
    < np.abs(gt_times[indices] - est_times)
)
indices[use_previous] = previous[use_previous]

time_error = np.abs(gt_times[indices] - est_times)
valid = time_error <= 0.02

matched_est = est[valid, 1:4]
matched_gt = gt[indices[valid], 1:4]

if len(matched_est) < 10:
    raise RuntimeError(
        f"Only {len(matched_est)} matched poses. "
        "Check timestamps and association."
    )

# Rigid Umeyama/Kabsch alignment: rotation + translation, no scale correction.
# RGB-D SLAM should already estimate metric scale.
mean_est = matched_est.mean(axis=0)
mean_gt = matched_gt.mean(axis=0)

X = matched_est - mean_est
Y = matched_gt - mean_gt

U, _, Vt = np.linalg.svd(X.T @ Y)
R = U @ Vt

if np.linalg.det(R) < 0:
    U[:, -1] *= -1
    R = U @ Vt

aligned = X @ R + mean_gt
errors = np.linalg.norm(aligned - matched_gt, axis=1)

rmse = np.sqrt(np.mean(errors ** 2))
median = np.median(errors)
maximum = np.max(errors)

print("\n===== RGB-D SLAM Evaluation =====")
print(f"Estimated poses: {len(est)}")
print(f"Matched poses:   {len(errors)}")
print(f"Match coverage:  {100 * len(errors) / len(est):.1f}%")
print(f"ATE RMSE:        {rmse:.4f} m")
print(f"ATE median:      {median:.4f} m")
print(f"ATE maximum:     {maximum:.4f} m")
print(f"Mean timestamp difference: {time_error[valid].mean():.5f} s")

np.savetxt(
    RESULTS / "aligned_trajectory_comparison.txt",
    np.column_stack((est_times[valid], matched_gt, aligned, errors)),
    header="timestamp gt_x gt_y gt_z est_aligned_x est_aligned_y est_aligned_z error_m",
    fmt="%.8f",
)

# Plot 1: horizontal/top-down trajectory.
fig, ax = plt.subplots(figsize=(8, 6))
ax.plot(matched_gt[:, 0], matched_gt[:, 2],
        label="Ground truth", linewidth=2)
ax.plot(aligned[:, 0], aligned[:, 2],
        label="ORB-SLAM3 estimate", linewidth=1.5)
ax.set_xlabel("X (m)")
ax.set_ylabel("Z (m)")
ax.set_title("TUM RGB-D: Camera Trajectory")
ax.axis("equal")
ax.grid(True)
ax.legend()
fig.tight_layout()
fig.savefig(RESULTS / "trajectory_comparison.png", dpi=160)
plt.close(fig)

# Plot 2: error over time.
fig, ax = plt.subplots(figsize=(9, 4))
ax.plot(est_times[valid] - est_times[valid][0], errors)
ax.set_xlabel("Elapsed time (s)")
ax.set_ylabel("Position error (m)")
ax.set_title(f"Absolute Trajectory Error (RMSE = {rmse:.3f} m)")
ax.grid(True)
fig.tight_layout()
fig.savefig(RESULTS / "trajectory_error.png", dpi=160)
plt.close(fig)

print("\nSaved plots:")
print(RESULTS / "trajectory_comparison.png")
print(RESULTS / "trajectory_error.png")
