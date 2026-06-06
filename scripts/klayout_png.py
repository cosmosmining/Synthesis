# Headless GDS/DEF -> PNG. Run:
#   QT_QPA_PLATFORM=offscreen KL_IN=in.gds KL_OUT=out.png klayout -b -r scripts/klayout_png.py
import os, pya
lv = pya.LayoutView()
lv.load_layout(os.environ["KL_IN"], 0)
lv.max_hier()
lv.zoom_fit()
lv.save_image(os.environ["KL_OUT"], int(os.environ.get("KL_W", 1600)),
              int(os.environ.get("KL_H", 1600)))
print("saved", os.environ["KL_OUT"])
