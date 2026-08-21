---
name: glmv-grounding
description: 使用 GLM-V 对图像/视频中的目标进行定位（2D/3D 边界框、点、多边形、目标跟踪）并可视化。当用户说"框出图中的xx"、"定位目标"、"跟踪视频里的物体"时使用。
category: 智谱 GLM
source: zai-org/glmv-grounding
---

# GLM-V Grounding Skill

Extract and visualize grounding results produced by GLM-V. Grounding coordinates in model outputs may appear as 2D bounding boxes, Objects Detection JSON, 2D points, 3D bounding boxes, and target-tracking JSON.

**Note**: GLM-V outputs coordinates where **x and y are relative coordinates normalized to 0-1000**: x=round(x_pixel/W*1000), y=round(y_pixel/H*1000). The origin is the top-left corner.

**Note**: If the prompt does not explicitly specify a grounding format (for example, "find the location of xxx" or "draw a box around xxx"), treat the request as 2D bounding boxes by default.

## When to use

* **Ground targets in images**: obtain grounding results for any prompt-described target, with output formats such as 2D bounding box (default), 2D points, and 3D bounding box.
* **Track targets in videos**: obtain tracking results in a video, output format like `{"0": [{"label": ..., "bbox_2d": ...}, ...], ...}`.
* **Use utility functions for extraction, conversion, and visualization**.

## Setup your API Key

Configure `ZHIPU_API_KEY` to call the GLM-V API.

1. Get your API key: https://www.bigmodel.cn/usercenter/proj-mgmt/apikeys
2. Configure it with: `python scripts/config_setup.py setup --api-key YOUR_KEY`

## Runtime Dependencies

```bash
pip install -r scripts/requirements.txt
```

Main packages: `requests`, `Pillow`, `opencv-python`, `numpy`, `matplotlib`, `decord`. System dependency for video visualization: `ffmpeg`.

## General workflow

```
Input (image or video + Prompt)
    |
    ▼
Run glm_grounding_cli.py to get grounding results (natural language)
    |
    ▼
Return results (grounding results, visualized image or video)
```

## How to Use

### Run glm_grounding_cli.py to get grounding results

* Ground any target in an image

```bash
python scripts/glm_grounding_cli.py --image-url "URL provided by user" --prompt "description of target for grounding"
```

* Track any target in a video

```bash
python scripts/glm_grounding_cli.py --video-url /path/to/video.mp4 --prompt "description of target for tracking" --visualize --visualization-dir "./vis"
```

### Reply with grounding results

After receiving a grounding prompt from the user, your direct reply should be natural language that includes grounding coordinates. Coordinates are relative values in [0, 1000].

**Unless otherwise specified, grounding results should use the following data formats**:

* **2D bounding boxes**: `[[x1, y1, x2, y2], ...]` — list of boxes, each box has 4 coordinate values
* **2D points**: `[[x, y], ...]` — list of points, each point has 2 coordinate values
* **2D polygon**: `[[x1, y1], [x2, y2], ...]` — polygon coordinate list
* **3D bounding boxes**: `[{"bbox_3d":[x_center, y_center, z_center, x_size, y_size, z_size, roll, pitch, yaw],"label":"category"}, ...]`
* **Objects Detection JSON**: `[{'label': 'category', 'bbox_2d': [x1, y1, x2, y2]}, ...]`
* **Video Objects Tracking JSON**: `{0: [{'label': 'car-1', 'bbox_2d': [1,2,3,4]}, ...], 1: [...]}` — keys are frame indices

## Python example

```python
# 1. User grounding request
image = "https://example.com/image.jpg"
prompt = "Please box all people wearing Santa hats in the image and tell me their coordinates. Use red boxes, line thickness 3, and label format 'SantaHat-i'."

# 2. Get grounding results
# python scripts/glm_grounding_cli.py --image-url $image --prompt $prompt --visualize --visualization-dir "./vis"
# Result:
# {
#     "ok": True,
#     "grounding_result": [[100, 200, 300, 400], [500, 600, 700, 800]],
#     "visualizations_result": {"visualized_image": "./vis/image_vis.jpg"},
#     "raw_result": "...",
#     "error": None,
# }
```

## Utility function quick reference

| Function | Purpose |
| --- | --- |
| parse_coordinates_from_response(response_str, coords_type='bbox', ...) | Parse all coordinate results from model responses (2D bbox, point, polygon) |
| parse_3d_boxes_from_response(response_str) | Parse all 3D boxes and labels from model responses |
| parse_detection_from_response(response_str) | Parse all 2D detection results (Objects Detection JSON) |
| parse_mot_from_response(response_str) | Parse video object tracking results (MOT JSON) |
| visualize_boxes(img_path, boxes, labels, ...) | Draw 2D boxes on images with labels, custom colors, line thickness |
| visualize_points(img_path, points, labels, ...) | Draw points on images with labels, custom size and colors |
| visualize_3d_boxes_glmv_simple(...) | Draw projected 3D boxes using camera intrinsics |
| visualize_mot(video_path, mot_js, ...) | Draw MOT boxes on each video frame with labels |

## Common errors

* **Coordinate values exceed 1000**: the model may have produced unnormalized coordinates. Re-query the model and explicitly require output coordinates to be relative values normalized to 0-1000 based on image size.
