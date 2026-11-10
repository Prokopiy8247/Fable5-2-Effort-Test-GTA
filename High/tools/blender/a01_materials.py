"""Shared palette for the 'Marlow Bay' flat-shaded low-poly art direction."""
import sys
sys.path.insert(0, r"G:\YouTube\Fable 5.2 Effort Test GTA\High\tools\blender")
import importlib, gta_lib
importlib.reload(gta_lib)
from gta_lib import *

P = [
    # vehicles
    ("M_Paint", "#d8402f", 0.35, 0.3), ("M_Paint2", "#f2efe6", 0.4, 0.2),
    ("M_Tire", "#1b1c20", 0.9, 0.0), ("M_Rim", "#c9ccd2", 0.3, 0.8), ("M_Chrome", "#dfe3e8", 0.2, 0.9),
    ("M_Black", "#18191c", 0.7, 0.1), ("M_Interior", "#2e2f36", 0.85, 0.0), ("M_Seat", "#4a3f39", 0.9, 0.0),
    ("M_Plate", "#f4f1e4", 0.6, 0.0), ("M_Under", "#101114", 0.9, 0.0),
    # generic
    ("M_White", "#f1eee6", 0.7, 0.0), ("M_Cream", "#e8dcc0", 0.8, 0.0), ("M_Grey", "#8c8f96", 0.8, 0.0),
    ("M_DarkGrey", "#4a4d55", 0.85, 0.0), ("M_Concrete", "#b9b4a8", 0.9, 0.0), ("M_ConcreteDark", "#8a877f", 0.9, 0.0),
    ("M_Asphalt", "#3a3c42", 0.95, 0.0), ("M_Metal", "#9aa0a8", 0.4, 0.8), ("M_MetalDark", "#50545c", 0.5, 0.7),
    ("M_Steel", "#bcc2c9", 0.35, 0.85), ("M_Rust", "#8f5134", 0.85, 0.2),
    ("M_Red", "#c8382b", 0.6, 0.0), ("M_Orange", "#e98a2b", 0.6, 0.0), ("M_Yellow", "#f0c330", 0.6, 0.0),
    ("M_Green", "#4f9a4b", 0.8, 0.0), ("M_Teal", "#2f9c95", 0.6, 0.0), ("M_Blue", "#2f6fba", 0.6, 0.0),
    ("M_Navy", "#1f2d4d", 0.6, 0.0), ("M_Purple", "#7a4a9c", 0.6, 0.0), ("M_Pink", "#e27a8c", 0.6, 0.0),
    ("M_Brown", "#6e4a33", 0.85, 0.0), ("M_Wood", "#a2764a", 0.85, 0.0), ("M_WoodDark", "#6b4a30", 0.9, 0.0),
    ("M_Brick", "#a8553f", 0.9, 0.0), ("M_BrickDark", "#7c4234", 0.9, 0.0), ("M_Sand", "#e2cf9c", 0.95, 0.0),
    ("M_Terracotta", "#c56b46", 0.85, 0.0), ("M_Stucco", "#ead9b8", 0.9, 0.0), ("M_StuccoPink", "#e8b7a0", 0.9, 0.0),
    ("M_StuccoBlue", "#a9c7d6", 0.9, 0.0), ("M_StuccoMint", "#b5d8c0", 0.9, 0.0), ("M_Roof", "#5a4038", 0.9, 0.0),
    ("M_RoofRed", "#b5523a", 0.85, 0.0), ("M_RoofSlate", "#4b5560", 0.85, 0.0),
    ("M_Leaf", "#4d8f3e", 0.9, 0.0), ("M_LeafDark", "#346b35", 0.9, 0.0), ("M_LeafLight", "#7fb450", 0.9, 0.0),
    ("M_Palm", "#5fa04a", 0.9, 0.0), ("M_Trunk", "#6a4a34", 0.95, 0.0), ("M_Rock", "#8d8a84", 0.95, 0.0),
    ("M_RockDark", "#6a6964", 0.95, 0.0),
    # characters
    ("M_Skin", "#d9a27e", 0.8, 0.0), ("M_Shirt", "#3f7fbf", 0.85, 0.0), ("M_Sleeve", "#3f7fbf", 0.85, 0.0),
    ("M_Pants", "#30384f", 0.9, 0.0), ("M_Shin", "#30384f", 0.9, 0.0), ("M_Shoes", "#26221f", 0.8, 0.0),
    ("M_Hair", "#3a2a1e", 0.9, 0.0), ("M_Eye", "#1a1a1e", 0.5, 0.0), ("M_Fur", "#a9794c", 0.95, 0.0),
    ("M_FurDark", "#5d4634", 0.95, 0.0), ("M_FurLight", "#e9e1d0", 0.95, 0.0), ("M_Fish", "#7fa9c9", 0.5, 0.2),
    ("M_Shark", "#6f7c88", 0.6, 0.1),
    # weapons
    ("M_Gun", "#2a2c31", 0.45, 0.7), ("M_GunLight", "#70757d", 0.4, 0.8), ("M_Grip", "#3d3027", 0.8, 0.0),
    ("M_Polymer", "#34373c", 0.75, 0.1), ("M_Olive", "#5b6340", 0.8, 0.0), ("M_Blade", "#d5dade", 0.25, 0.9),
]
for name, col, r, m in P:
    mat(name, col, r, m)

# emissive / special
mat("M_Glass", "#22343c", 0.08, 0.3, alpha=0.5)
mat("M_Headlight", "#fff3cf", 0.3, 0.0, emit="#fff3cf", emit_strength=1.5)
mat("M_Taillight", "#a8141a", 0.4, 0.0, emit="#ff1a22", emit_strength=0.6)
mat("M_Indicator", "#e8861d", 0.4, 0.0, emit="#ff9a22", emit_strength=0.4)
mat("M_Siren_R", "#c41c1c", 0.3, 0.0, emit="#ff2020", emit_strength=0.6)
mat("M_Siren_B", "#1c3fc4", 0.3, 0.0, emit="#2050ff", emit_strength=0.6)
mat("M_TaxiSign", "#f6d24a", 0.4, 0.0, emit="#ffd84a", emit_strength=1.0)
mat("M_WindowLit", "#3a4e63", 0.15, 0.4)
mat("M_WindowDark", "#2c3d4e", 0.15, 0.4)
mat("M_ShopGlass", "#5f8fa6", 0.1, 0.3, alpha=0.55)
mat("M_Neon_A", "#ff4f8b", 0.4, 0.0, emit="#ff4f8b", emit_strength=3.0)
mat("M_Neon_B", "#34e0d0", 0.4, 0.0, emit="#34e0d0", emit_strength=3.0)
mat("M_Neon_C", "#ffc93c", 0.4, 0.0, emit="#ffc93c", emit_strength=3.0)
mat("M_LampGlow", "#fff0c0", 0.4, 0.0, emit="#ffe9a8", emit_strength=2.0)
mat("M_TL_Red", "#3a0c0c", 0.4, 0.0)
mat("M_TL_Yellow", "#3a300c", 0.4, 0.0)
mat("M_TL_Green", "#0c3a14", 0.4, 0.0)
mat("M_Canopy", "#f15a3a", 0.8, 0.0, double=True)
mat("M_Canopy2", "#f6e7c8", 0.8, 0.0, double=True)
mat("M_Fabric", "#d6c8a8", 0.9, 0.0, double=True)
mat("M_Water", "#2a8fa8", 0.1, 0.0, alpha=0.7)
mat("M_Gold", "#e3b341", 0.3, 0.9)
mat("M_Cash", "#5fae5a", 0.7, 0.0, emit="#5fae5a", emit_strength=0.3)
mat("M_HealthRed", "#e8443a", 0.6, 0.0, emit="#e8443a", emit_strength=0.3)
mat("M_ArmorBlue", "#3d7fe0", 0.5, 0.2, emit="#3d7fe0", emit_strength=0.3)
print("materials:", len(bpy.data.materials))
