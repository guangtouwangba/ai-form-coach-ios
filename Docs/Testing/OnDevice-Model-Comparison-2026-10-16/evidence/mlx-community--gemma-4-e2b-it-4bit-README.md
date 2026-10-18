---
library_name: mlx
license: gemma
base_model: google/gemma-4-E2B-it
tags:
- mlx
- mlx-vlm
- gemma4
- image-text-to-text
---

# mlx-community/gemma-4-e2b-it-4bit

MLX conversion of [google/gemma-4-E2B-it](https://huggingface.co/google/gemma-4-E2B-it) for Apple silicon.

- Source revision: `70af34e20bd4b7a91f0de6b22675850c43922a03`
- Variant: `4bit`
- Converted with `mlx_vlm.convert` from the local `mlx-vlm` checkout.

## Usage

```bash
pip install mlx-vlm
python -m mlx_vlm.generate --model mlx-community/gemma-4-e2b-it-4bit --prompt "Describe this image." --image path/to/image.jpg
```
