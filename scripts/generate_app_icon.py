import os
import numpy as np
from PIL import Image, ImageFilter, ImageDraw
from scipy.ndimage import binary_fill_holes, gaussian_filter

def create_icons():
    # 1. 加载原图
    src_path = "resources/icon (1).png"
    im = Image.open(src_path).convert("RGBA")
    
    # 放大到 1000x1000 提高精度
    im = im.resize((1000, 1000), Image.Resampling.LANCZOS)
    arr = np.array(im, dtype=np.float32)
    
    alpha = arr[:, :, 3] / 255.0
    is_solid = alpha > 0.5
    filled = binary_fill_holes(is_solid)
    
    # 获取外围圆角轮廓（squircle）和内部 T 的精确 mask
    # 对 filled 进行轻微羽化使边缘极其顺滑
    squircle_mask = filled.astype(np.float32)
    squircle_mask = gaussian_filter(squircle_mask, sigma=1.2)
    
    # T 的内部区域
    t_raw = filled & (~is_solid)
    t_mask = gaussian_filter(t_raw.astype(np.float32), sigma=1.2)
    
    # 2. 生成黑底 + 纯白 T 的核心图标 (1000x1000)
    h, w = 1000, 1000
    base_img = np.zeros((h, w, 4), dtype=np.float32)
    
    # 背景为深邃纯黑（类似第二张图 ZCode，极弱微妙渐变增强质感：顶部 #1a1a1c，底部 #0f0f11）
    for y in range(h):
        ratio = y / float(h)
        bg_r = 26.0 * (1 - ratio) + 14.0 * ratio
        bg_g = 26.0 * (1 - ratio) + 14.0 * ratio
        bg_b = 28.0 * (1 - ratio) + 16.0 * ratio
        
        sq = squircle_mask[y]
        base_img[y, :, 0] = bg_r * sq
        base_img[y, :, 1] = bg_g * sq
        base_img[y, :, 2] = bg_b * sq
        base_img[y, :, 3] = sq * 255.0
    
    # 叠加纯白 T
    for c in range(3):
        base_img[:, :, c] = base_img[:, :, c] * (1.0 - t_mask) + 255.0 * t_mask
    base_img[:, :, 3] = np.maximum(base_img[:, :, 3], t_mask * 255.0)
    
    core_icon = Image.fromarray(np.clip(base_img, 0, 255).astype(np.uint8), "RGBA")
    
    # 保存一份专门用于首页等 UI 控件的高清无投影版本 (512x512)
    ui_icon = core_icon.resize((512, 512), Image.Resampling.LANCZOS)
    ui_icon.save("resources/icon.png")
    
    # 3. 按照 macOS HIG 规范制作 1024x1024 AppIcon（带标准 824x824 尺寸与微阴影，杜绝过大突兀感）
    canvas_size = 1024
    app_icon_canvas = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    
    # 标准 macOS 圆角图标尺寸约为 824x824
    target_icon_size = 824
    scaled_core = core_icon.resize((target_icon_size, target_icon_size), Image.Resampling.LANCZOS)
    
    # 创建阴影层
    shadow_offset_y = 18
    shadow_blur = 28
    shadow_alpha = 90
    
    shadow_mask = scaled_core.split()[3]
    shadow_img = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    # 黑色阴影
    shadow_base = Image.new("RGBA", (target_icon_size, target_icon_size), (0, 0, 0, shadow_alpha))
    shadow_base.putalpha(shadow_mask)
    
    pos_x = (canvas_size - target_icon_size) // 2
    pos_y = (canvas_size - target_icon_size) // 2
    
    # 将阴影稍微向下偏移并模糊
    shadow_img.paste(shadow_base, (pos_x, pos_y + shadow_offset_y))
    shadow_img = shadow_img.filter(ImageFilter.GaussianBlur(shadow_blur))
    
    # 合成阴影和主图标
    app_icon_canvas.alpha_composite(shadow_img)
    app_icon_canvas.paste(scaled_core, (pos_x, pos_y), scaled_core)
    
    app_icon_canvas.save("resources/TeXMini_1024.png")
    print("Successfully generated resources/icon.png and resources/TeXMini_1024.png")

if __name__ == "__main__":
    create_icons()
