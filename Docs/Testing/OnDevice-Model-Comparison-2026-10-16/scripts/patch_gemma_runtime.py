"""Fix MLX-VLM 0.6.0's shared-KV module tree to match the complete checkpoint.
Matches ml-explore/mlx-swift-lm 3.32.3 Gemma4Attention's shared-tail constructor.
Never bypasses strict weight loading or fabricates missing weights.
"""
from pathlib import Path
import hashlib,difflib,json
B=Path(__file__).resolve().parents[1];p=Path('/tmp/coach-alternatives-venv/lib/python3.12/site-packages/mlx_vlm/models/gemma4/language.py');original=p.read_text()
audit=json.loads((B/'evidence/gemma4-runtime-patch.json').read_text())
actual=hashlib.sha256(original.encode()).hexdigest()
if actual==audit['patchedSHA256']:
 print('Already patched; verified source hash');raise SystemExit(0)
assert actual==audit['originalSHA256'],'Unexpected library source: refusing to patch'
assert original.count('if not kv_shared_only:')==2
fixed=original.replace('        self.kv_shared_only = kv_shared_only','        self.kv_shared_only = kv_shared_only\n        first_shared = config.num_hidden_layers - getattr(config, "num_kv_shared_layers", 0)\n        self.is_kv_shared_layer = layer_idx >= first_shared > 0').replace('if not kv_shared_only:','if not (kv_shared_only or self.is_kv_shared_layer):')
(B/'evidence/gemma4-shared-kv.patch').write_text(''.join(difflib.unified_diff(original.splitlines(True),fixed.splitlines(True),fromfile='mlx_vlm/models/gemma4/language.py',tofile='mlx_vlm/models/gemma4/language.py')))
p.write_text(fixed)
(B/'evidence/gemma4-runtime-patch.json').write_text(json.dumps({'runtime':'mlx-vlm 0.6.0','originalSHA256':hashlib.sha256(original.encode()).hexdigest(),'patchedSHA256':hashlib.sha256(fixed.encode()).hexdigest(),'reason':'Checkpoint has no K/V projections or K norm in layers 15..34 because num_kv_shared_layers=20. Original Python module declared 60 nonexistent parameters. Preserve strict load; omit unused modules according to shared-KV architecture, consistent with Swift upstream 3.32.3.','independentSource':'https://github.com/ml-explore/mlx-swift-lm/blob/3.32.3/Libraries/MLXVLM/Models/Gemma4.swift'},indent=2))
print('Patched shared-KV constructor; strict weight loading retained')
