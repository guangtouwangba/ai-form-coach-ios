---
base_model: Qwen/Qwen3.5-4B
library_name: mlx
tags:
  - mlx
  - qwen3.5
  - vision-language-model
  - quantized
  - 4bit
license: apache-2.0
---

# Qwen3.5-4B-MLX-4bit

This is a 4-bit quantized MLX version of [Qwen/Qwen3.5-4B](https://huggingface.co/Qwen/Qwen3.5-4B) for Apple Silicon.

## Model Details

- **Original Model:** [Qwen/Qwen3.5-4B](https://huggingface.co/Qwen/Qwen3.5-4B)
- **Quantization:** 4-bit (5.347 bits per weight)
- **Group Size:** 64
- **Format:** MLX SafeTensors
- **Framework:** [mlx-vlm](https://github.com/Blaizzy/mlx-vlm)
- **Disk Size:** ~2.9G

## Conversion Details

This model was converted using `mlx-vlm` from the [`pc/fix-qwen35-predicate`](https://github.com/Blaizzy/mlx-vlm/tree/pc/fix-qwen35-predicate) branch, which includes fixes for Qwen3.5 model support (proper handling of MoE gate layers, `shared_expert_gate`, and `A_log` casting).

**Conversion command:**
```bash
python3 -m mlx_vlm convert \
  --hf-path "Qwen/Qwen3.5-4B" \
  --mlx-path "./Qwen3.5-4B-MLX-4bit" \
  -q --q-bits 4 --q-group-size 64
```

## Important Note

A better, more optimized conversion may be available from **@Prince** ([@Blaizzy](https://huggingface.co/Blaizzy)) in the MLX VLM community. Check the [mlx-community](https://huggingface.co/mlx-community) organization for updated versions as official Qwen3.5 support is merged into the main `mlx-vlm` branch.

## Related Models

- **bf16 (full precision):** [mlx-community/Qwen3.5-4B-MLX-bf16](https://huggingface.co/mlx-community/Qwen3.5-4B-MLX-bf16)
- **8-bit quantized:** [mlx-community/Qwen3.5-4B-MLX-8bit](https://huggingface.co/mlx-community/Qwen3.5-4B-MLX-8bit)
- **Original:** [Qwen/Qwen3.5-4B](https://huggingface.co/Qwen/Qwen3.5-4B)

## Usage

```python
from mlx_vlm import load, generate

model, processor = load("mlx-community/Qwen3.5-4B-MLX-4bit")

output = generate(
    model,
    processor,
    prompt="Describe this image.",
    image="path/to/image.jpg",
    max_tokens=512
)
print(output)
```

**CLI:**
```bash
python3 -m mlx_vlm.generate \
  --model mlx-community/Qwen3.5-4B-MLX-4bit \
  --image path/to/image.jpg \
  --prompt "Describe this image."
```

## License

This model inherits the [Apache 2.0 license](https://huggingface.co/Qwen/Qwen3.5-4B) from the original Qwen model.
