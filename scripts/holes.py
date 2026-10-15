import sys, glob, numpy as np
from PIL import Image
from scipy import ndimage
# usage: holes.py dir prefix keyhex mode(any|exterior)
d, prefix, key, mode = sys.argv[1:5]
k = np.array([int(key[i:i+2], 16) for i in (0, 2, 4)]) / 255
for f in sorted(glob.glob(f'{d}/{prefix}-*.png')):
    a = np.array(Image.open(f).convert('RGBA')).astype(np.float32) / 255
    rgb, al = a[:, :, :3], a[:, :, 3]
    dist = np.sqrt(((rgb - k) ** 2).sum(-1))
    keyish = (dist < 0.22) & (al > 0)
    if mode == 'exterior':
        ext = al < 0.1
        lab, _ = ndimage.label(keyish | ext)
        t = np.unique(lab[ext]); t = t[t > 0]
        keyish = np.isin(lab, t) & ~ext
    else:
        keyish = ndimage.binary_opening(keyish, iterations=1)
    soft = ndimage.gaussian_filter(ndimage.binary_dilation(keyish, iterations=1).astype(np.float32), 0.7)
    a[:, :, 3] = al * (1 - np.clip(soft * 1.3, 0, 1))
    # despill: limit the key's dominant channels to the others
    if key.upper() == 'FF00FF':
        m = np.minimum(rgb[:, :, 0], rgb[:, :, 2]); lim = rgb[:, :, 1] + 0.03; ex = np.clip(m - lim, 0, None)
        rgb[:, :, 0] -= ex; rgb[:, :, 2] -= ex
    if key.upper() == '00FF00':
        rgb[:, :, 1] = np.minimum(rgb[:, :, 1], np.maximum(rgb[:, :, 0], rgb[:, :, 2]) + 0.03)
    if key.upper() == '0000FF':
        rgb[:, :, 2] = np.minimum(rgb[:, :, 2], np.maximum(rgb[:, :, 0], rgb[:, :, 1]) + 0.03)
    a[:, :, :3] = rgb
    Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)).save(f, optimize=True)
print(prefix, 'ok')
