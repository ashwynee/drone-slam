from pathlib import Path
import numpy as np
import matplotlib.pyplot as plt

ROOT = Path.home() / "drone-slam"
DATA = Path.home() / "datasets/euroc/MH_01_easy/mav0"
OUT = ROOT / "results/euroc_mh01"
OUT.mkdir(parents=True, exist_ok=True)

# ORB-SLAM3 trajectory: timestamp_ns tx ty tz qx qy qz qw
est = np.loadtxt(OUT / "CameraTrajectory.txt")
if est.ndim != 2 or est.shape[1] < 8:
    raise ValueError("Unexpected CameraTrajectory.txt format")

# EuRoC ground truth columns:
# timestamp, position xyz, quaternion qw qx qy qz, ...
gt = np.loadtxt(
    DATA / "state_groundtruth_estimate0/data.csv",
    delimiter=",", comments="#"
)

# Preserve useful timestamp precision by subtracting a common epoch first.
t0 = min(est[0, 0], gt[0, 0])
est_t = (est[:, 0] - t0) * 1e-9
gt_t = (gt[:, 0] - t0) * 1e-9

# T_b_c1: transform from left-camera coordinates to body/IMU coordinates.
T_b_c = np.array([
    [ 0.0148655429818, -0.999880929698,  0.00414029679422, -0.0216401454975],
    [ 0.999557249008,  0.0149672133247,  0.025715529948,  -0.064676986768],
    [-0.0257744366974, 0.00375618835797, 0.999660727178,   0.00981073058949],
    [0, 0, 0, 1]
])
R_b_c = T_b_c[:3, :3]
t_b_c = T_b_c[:3, 3]

def quat_wxyz_to_R(q):
    q = np.asarray(q, dtype=float)
    q = q / np.linalg.norm(q)
    w, x, y, z = q
    return np.array([
        [1-2*(y*y+z*z), 2*(x*y-z*w),   2*(x*z+y*w)],
        [2*(x*y+z*w),   1-2*(x*x+z*z), 2*(y*z-x*w)],
        [2*(x*z-y*w),   2*(y*z+x*w),   1-2*(x*x+y*y)]
    ])

# Ground-truth body pose -> ground-truth left-camera position.
gt_cam_positions = []
for row in gt:
    p_w_b = row[1:4]
    R_w_b = quat_wxyz_to_R(row[4:8])
    gt_cam_positions.append(p_w_b + R_w_b @ t_b_c)
gt_cam_positions = np.asarray(gt_cam_positions)

# Match each estimated pose to its nearest ground-truth timestamp.
idx = np.searchsorted(gt_t, est_t)
idx = np.clip(idx, 0, len(gt_t)-1)
prev = np.clip(idx-1, 0, len(gt_t)-1)
idx[np.abs(gt_t[prev]-est_t) < np.abs(gt_t[idx]-est_t)] = prev[
    np.abs(gt_t[prev]-est_t) < np.abs(gt_t[idx]-est_t)
]
dt = np.abs(gt_t[idx] - est_t)
valid = dt <= 0.01

est_xyz = est[valid, 1:4]
gt_xyz = gt_cam_positions[idx[valid]]

if len(est_xyz) < 10:
    raise RuntimeError(
        f"Only {len(est_xyz)} timestamp matches within 10 ms. "
        "Check timestamps and trajectory files."
    )

# Rigid alignment (rotation + translation, no scale correction).
# Row-vector convention: aligned = (estimate - mean) @ R + mean_gt
mean_e = est_xyz.mean(axis=0)
mean_g = gt_xyz.mean(axis=0)
X = est_xyz - mean_e
Y = gt_xyz - mean_g
U, _, Vt = np.linalg.svd(X.T @ Y)
R = U @ Vt
if np.linalg.det(R) < 0:
    U[:, -1] *= -1
    R = U @ Vt

aligned = X @ R + mean_g
errors = np.linalg.norm(aligned - gt_xyz, axis=1)

rmse = np.sqrt(np.mean(errors**2))
median = np.median(errors)
maximum = np.max(errors)

print("\n===== EuRoC MH_01_easy: Stereo-Inertial Evaluation =====")
print(f"Estimated poses: {len(est)}")
print(f"Matched poses (within 10 ms): {len(errors)}")
print(f"Match coverage: {100*len(errors)/len(est):.2f}%")
print(f"ATE RMSE:   {rmse:.4f} m")
print(f"ATE median: {median:.4f} m")
print(f"ATE max:    {maximum:.4f} m")
print(f"Mean timestamp difference: {dt[valid].mean()*1000:.3f} ms")

np.savetxt(
    OUT / "aligned_trajectory.txt",
    np.column_stack((est_t[valid], gt_xyz, aligned, errors)),
    header="time_s gt_cam_x gt_cam_y gt_cam_z est_aligned_x est_aligned_y est_aligned_z error_m",
    fmt="%.8f"
)

fig, ax = plt.subplots(figsize=(8, 6))
ax.plot(gt_xyz[:, 0], gt_xyz[:, 1], label="Ground truth camera")
ax.plot(aligned[:, 0], aligned[:, 1], label="ORB-SLAM3 estimate")
ax.set_xlabel("X (m)")
ax.set_ylabel("Y (m)")
ax.set_title("EuRoC MH_01_easy: Camera Trajectory")
ax.axis("equal")
ax.grid(True)
ax.legend()
fig.tight_layout()
fig.savefig(OUT / "trajectory_comparison.png", dpi=160)
plt.close(fig)

fig, ax = plt.subplots(figsize=(9, 4))
ax.plot(est_t[valid] - est_t[valid][0], errors)
ax.set_xlabel("Elapsed time (s)")
ax.set_ylabel("Position error (m)")
ax.set_title(f"ATE after rigid alignment (RMSE = {rmse:.3f} m)")
ax.grid(True)
fig.tight_layout()
fig.savefig(OUT / "trajectory_error.png", dpi=160)
plt.close(fig)

print("\nSaved results to:", OUT)
