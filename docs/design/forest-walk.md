# 森林漫步

在「外观与主题」中选择「森林漫步」。经典漫画、童话绘本继续保留；默认主题不变。

- 森林只出现在宠物管理的预览场景，不覆盖词汇阅读区和参数检查器。
- 预览叠加实际选中的宠物素材，造型和动画选择不受主题影响。
- 侧栏空间足够时展示小幅蕨叶插画；紧凑窗口隐藏插画，优先保留导航。
- 气泡继续沿用现有词条排版，只调整主题色，不加森林壁纸。
- 主题选择保存于现有设置，不迁移、删除或重写词库和学习记录。

## 素材

使用内置 image_gen 生成原创位图，没有复制 Pinterest 或其他网站的素材。

- `Sources/CodexPetApp/Resources/Themes/forest-clearing.png`：不含宠物或文字的独立背景。
- `Sources/CodexPetApp/Resources/Themes/forest-ferns.png`：带透明通道的侧栏插画。

### 场景生成提示词

Use case: illustration-story. Create ONE original landscape background asset for the Forest Walk theme in PetPetKnows. Reference is only for the illustration style and the forest preview section; do NOT recreate the interface. Output a wide 3:2 landscape illustration, no UI, no borders, no writing, NO animals or characters. Charming refined hand-painted gouache woodland in daylight: leafy green trees framing both sides and top edges, ferns and tiny wildflowers near edges, a small clear blue stream and modest wooden footbridge on the right midground, soft distant hills and pale sky. Main central 45 percent must be an uncluttered bright grassy clearing suitable for overlaying an animated pet. Ground horizon around middle, centered pet would stand at 75% image height. Soft natural shapes, delicate textured brushwork, cohesive restrained emerald/jade, soft sky blue, leafy greens, small warm flower accents. Not photorealistic, not pixel art, no fantasy buildings, no bokeh/orbs/gradients. Light elegant calm composition, detail at the edges, not visually noisy. Keep bottom 15% nearly white with natural illustrated paper fade so the stage transitions softly into a white macOS application. Opaque image background.

### 侧栏生成提示词

Use case: illustration-story. One tiny elegant woodland botanical vignette for the footer of a macOS app sidebar. Genuine transparent background. A small cluster of two delicate jade-green fern fronds, three grassy sprigs, one little smooth gray stone, and two very small coral wildflowers. Refined light hand-painted gouache style with delicate natural texture, calm and airy. Composition horizontal 3:2, foliage rooted together near bottom center. Sparse rather than dense; no frame, no text, no characters, no pot, no entire landscape, no shadow box, no extra objects. Muted green leaves with enough contrast on very pale gray. Design to remain legible at 100x65 pixels. Transparent background, no white square.
