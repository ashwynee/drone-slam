from pathlib import Path
import numpy as np
from scipy.spatial.transform import Rotation, Slerp
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

D = Path.home() / "drone-slam/results/live_gazebo"
GT_FILE = D / "ground_truth.txt"
SLAM_FILE = D / "LiveCameraTrajectory.txt"

# The autonomous flight window from our previous analysis.
START, END = 2243.0, 2258.0

# Camera centre relative to the drone body, in metres.
CAMERA_OFFSET = np.array([0.12, 0.03, 0.242])

MIN_SPEED = 0.08
MAX_GAP = 0.75


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
        raise RuntimeError(f"No valid TUM rows in {path}")

    return np.asarray(rows, dtype=float)


def interpolate_positions(times, trajectory):
    return np.column_stack([
        np.interp(times, trajectory[:, 0], trajectory[:, axis])
        for axis in (1, 2, 3)
    ])


def align_similarity(estimated, reference):
    """Fit reference ~= scale * R * estimated + translation."""
    mx = estimated.mean(axis=0)
    my = reference.mean(axis=0)

    X = estimated - mx
    Y = reference - my

    variance = np.mean(np.sum(X * X, axis=1))
    if variance < 1e-12:
        raise RuntimeError("Insufficient trajectory variation for alignment.")

    U, singular_values, Vt = np.linalg.svd(Y.T @ X / len(X))

    correction = np.eye(3)
    if np.linalg.det(U @ Vt) < 0:
        correction[2, 2] = -1

    R = U @ correction @ Vt
    scale = np.sum(singular_values * np.diag(correction)) / variance

    aligned = scale * (X @ R.T) + my
    errors = np.linalg.norm(aligned - reference, axis=1)

    return scale, aligned, errors


def summarize(label, errors, scale):
    print(f"\n{label}")
    print(f"  Estimated scale: {scale:.6f}")
    print(f"  ATE RMSE:        {np.sqrt(np.mean(errors**2)):.4f} m")
    print(f"  Median error:    {np.median(errors):.4f} m")
    print(f"  95th percentile: {np.percentile(errors, 95):.4f} m")
    print(f"  Maximum error:   {np.max(errors):.4f} m")


# Load and sort the original files.
gt = load_tum(GT_FILE)
slam = load_tum(SLAM_FILE)

gt = gt[np.argsort(gt[:, 0])]
slam = slam[np.argsort(slam[:, 0])]

# Remove duplicate GT timestamps.
_, unique_idx = np.unique(gt[:, 0], return_index=True)
gt = gt[np.sort(unique_idx)]

# Normalize GT quaternions (TUM order: qx, qy, qz, qw).
q = gt[:, 4:8]
q_norms = np.linalg.norm(q, axis=1)
if np.any(q_norms < 1e-8):
    raise RuntimeError("Ground truth contains invalid zero-length quaternions.")
gt[:, 4:8] = q / q_norms[:, None]

# Restrict the estimate to the requested flight interval and GT overlap.
valid = (
    (slam[:, 0] >= max(START, gt[0, 0])) &
    (slam[:, 0] <= min(END, gt[-1, 0]))
)
est = slam[valid]

if len(est) < 10:
    raise RuntimeError(
        f"Only {len(est)} SLAM poses in the flight window. "
        "Check the trajectory timestamps and selected window."
    )

t = est[:, 0]
slam_xyz = est[:, 1:4]

# Interpolate body position and orientation at each SLAM image timestamp.
body_xyz = interpolate_positions(t, gt)
gt_rotations = Rotation.from_quat(gt[:, 4:8])
orientation_interpolator = Slerp(gt[:, 0], gt_rotations)
body_rotations_at_t = orientation_interpolator(t)

# Transform body ground truth into camera-centre ground truth.
offsets_world = body_rotations_at_t.apply(
    np.tile(CAMERA_OFFSET, (len(t), 1))
)
camera_xyz = body_xyz + offsets_world

# Identify moving sections. Ignore intervals spanning large timestamp gaps.
dt = np.diff(t)
distance = np.linalg.norm(np.diff(camera_xyz, axis=0), axis=1)

speed = np.zeros_like(dt)
valid_dt = (dt > 1e-6) & (dt <= MAX_GAP)
speed[valid_dt] = distance[valid_dt] / dt[valid_dt]

moving_intervals = valid_dt & (speed > MIN_SPEED)
moving = np.zeros(len(t), dtype=bool)
moving[:-1] |= moving_intervals
moving[1:] |= moving_intervals

if moving.sum() < 10:
    raise RuntimeError(
        f"Only {moving.sum()} moving SLAM poses found. "
        "Inspect the flight window and movement threshold."
    )

# Fit both comparisons on the same moving timestamps.
X = slam_xyz[moving]
Y_body = body_xyz[moving]
Y_camera = camera_xyz[moving]
moving_t = t[moving]

scale_body, aligned_body, errors_body = align_similarity(X, Y_body)
scale_camera, aligned_camera, errors_camera = align_similarity(X, Y_camera)

print("\nCAMERA-CENTRE CORRECTED FLIGHT EVALUATION")
print(f"Flight window: {START:.2f}–{END:.2f} s")
print(f"Ground-truth rows loaded: {len(gt)}")
print(f"SLAM rows loaded: {len(slam)}")
print(f"SLAM poses in flight window: {len(est)}")
print(f"Moving poses evaluated: {moving.sum()}")
print(f"Evaluated timestamps: {moving_t[0]:.3f}–{moving_t[-1]:.3f} s")
print(f"Camera mount offset: {CAMERA_OFFSET.tolist()} m")

summarize("BODY-CENTRE COMPARISON (uncorrected)", errors_body, scale_body)
summarize("CAMERA-CENTRE COMPARISON (extrinsics corrected)",
          errors_camera, scale_camera)

print("\nThese are same-flight similarity-aligned ATE values.")
print("They are not independent metric-accuracy measurements.")

# Save a separate CSV; original trajectories remain untouched.
csv_file = D / "camera_center_evaluation.csv"
csv_data = np.column_stack((
    moving_t,
    Y_body,
    Y_camera,
    X,
    aligned_camera,
    errors_camera,
    errors_body
))
np.savetxt(
    csv_file,
    csv_data,
    delimiter=",",
    header=(
        "timestamp,"
        "body_gt_x,body_gt_y,body_gt_z,"
        "camera_gt_x,camera_gt_y,camera_gt_z,"
        "slam_raw_x,slam_raw_y,slam_raw_z,"
        "slam_aligned_x,slam_aligned_y,slam_aligned_z,"
        "camera_center_error_m,body_center_error_m"
    ),
    comments=""
)

# Plot camera-centre path comparison.
fig, ax = plt.subplots(figsize=(9, 7))
ax.plot(Y_camera[:, 0], Y_camera[:, 1],
        label="Corrected camera-centre ground truth")
ax.plot(aligned_camera[:, 0], aligned_camera[:, 1],
        label="ORB-SLAM3 aligned trajectory")
ax.set_xlabel("World X (m)")
ax.set_ylabel("World Y (m)")
ax.set_title("Camera-centre trajectory comparison")
ax.axis("equal")
ax.grid(True)
ax.legend()
fig.tight_layout()
fig.savefig(D / "camera_center_trajectory.png", dpi=160)
plt.close(fig)

# Plot errors before and after applying the camera mount correction.
fig, ax = plt.subplots(figsize=(10, 4))
ax.plot(moving_t, errors_body, label="Body-centre comparison")
ax.plot(moving_t, errors_camera, label="Camera-centre corrected")
ax.set_xlabel("Gazebo simulation time (s)")
ax.set_ylabel("Aligned position error (m)")
ax.set_title("Effect of camera extrinsic correction")
ax.grid(True)
ax.legend()
fig.tight_layout()
fig.savefig(D / "camera_center_error.png", dpi=160)
plt.close(fig)

report = D / "camera_center_evaluation_metrics.txt"
report.write_text(
    "CAMERA-CENTRE EVALUATION\n"
    f"Flight window: {START:.2f}–{END:.2f} s\n"
    f"SLAM poses in window: {len(est)}\n"
    f"Moving poses evaluated: {moving.sum()}\n"
    f"Evaluated interval: {moving_t[0]:.3f}–{moving_t[-1]:.3f} s\n"
    f"Camera mount offset (body frame): {CAMERA_OFFSET.tolist()} m\n\n"
    f"Body-centre aligned ATE RMSE: "
    f"{np.sqrt(np.mean(errors_body**2)):.6f} m\n"
    f"Camera-centre corrected aligned ATE RMSE: "
    f"{np.sqrt(np.mean(errors_camera**2)):.6f} m\n"
    f"Corrected median error: {np.median(errors_camera):.6f} m\n"
    f"Corrected 95th percentile: "
    f"{np.percentile(errors_camera, 95):.6f} m\n"
    f"Corrected maximum error: {np.max(errors_camera):.6f} m\n\n"
    "Similarity alignment was fitted on the evaluated flight segment. "
    "These metrics are not independent metric-accuracy measurements.\n"
)

print("\nSaved new evaluation files:")
print(csv_file)
print(D / "camera_center_trajectory.png")
print(D / "camera_center_error.png")
print(report)