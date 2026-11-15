class_name UiGalleryPanel
extends Control

## 附录：CG・回想 & 音乐鉴赏界面（1:1 还原 PC 端 `sggallery990000` 7x4 布局、默认外观/变更外观切换、回想模式及 27 首简体中文曲名）。

signal close_requested()
signal play_bgm_requested(bgm_entry: String)
signal stop_bgm_requested()
signal play_op_requested()
signal recollection_requested(script_name: String, appearance_mode: int)

const CHAR_TABS := [
	{"key": "hi", "name": "皆原 陽茉莉", "prefix": "hiev", "tab_idx": 0},
	{"key": "ri", "name": "望月 理奈", "prefix": "riev", "tab_idx": 1},
	{"key": "yu", "name": "柊 ゆずゆ", "prefix": "yuev", "tab_idx": 2},
	{"key": "mi", "name": "沢渡 岬", "prefix": "miev", "tab_idx": 3},
]

const BGM_COUNT := 27

const BGM_TITLES_ZH: Array[String] = [
	"1 : theme of HIMARI ver.FRIEND",
	"2 : theme of RINA ver.FRIEND",
	"3 : theme of YUZUYU ver.FRIEND",
	"4 : theme of MISAKI ver.FRIEND",
	"5 : theme of HIMARI ver.LOVER",
	"6 : theme of RINA ver.LOVER",
	"7 : theme of YUZUYU ver.LOVER",
	"8 : theme of MISAKI ver.LOVER",
	"9 : 今日亦如往常",
	"10 : 伴随宜人微风",
	"11 : 橙色的天空",
	"12 : 星空的闪烁",
	"13 : FRIEND TO LOVER",
	"14 : 喧闹的日常",
	"15 : council of war",
	"16 : battle!",
	"17 : devote all one's energy",
	"18 : 怎么回事？",
	"19 : 最后献上绵长的吻",
	"20 : 比言语更重要的事",
	"21 : 欢欣雀跃的心情",
	"22 : LOVER TO ...",
	"23 : 描绘未来",
	"24 : quantum jump ver.inst",
	"25 : 开始恋爱吧！",
	"OP : quantum jump",
	"ED : 两人的相册",
]

# 自动从 setupforgallery 提取的 4 女主 CG 槽位表（支持默认外观 A / 变更外观 B）
const GALLERY_CG_SLOTS: Dictionary = {
	"hi": [
		{"thumb_a": "hiev01_A01S", "thumb_b": "", "cgs_a": ["hiev01_A01", "hiev01_A02"], "cgs_b": []},
		{"thumb_a": "hiev02_A01S", "thumb_b": "", "cgs_a": ["hiev02_A01", "hiev02_A02", "hiev02_A03", "hiev02_A04", "hiev02_A05", "hiev02_A06"], "cgs_b": []},
		{"thumb_a": "hiev03_A01S", "thumb_b": "hiev03_B01S", "cgs_a": ["hiev03_A01", "hiev03_A02", "hiev03_A03", "hiev03_A04", "hiev03_A05"], "cgs_b": ["hiev03_B01", "hiev03_B02", "hiev03_B03", "hiev03_B04", "hiev03_B05"]},
		{"thumb_a": "hiev04_A01S", "thumb_b": "", "cgs_a": ["hiev04_A01", "hiev04_A02", "hiev04_A03", "hiev04_A04", "hiev04_A05"], "cgs_b": []},
		{"thumb_a": "hiev05_A01S", "thumb_b": "", "cgs_a": ["hiev05_A01"], "cgs_b": []},
		{"thumb_a": "hiev06_A01S", "thumb_b": "", "cgs_a": ["hiev06_A01", "hiev06_A02", "hiev06_A03", "hiev06_A04", "hiev06_A05", "hiev06_A06"], "cgs_b": []},
		{"thumb_a": "hiev07_A01S", "thumb_b": "", "cgs_a": ["hiev07_A01", "hiev07_A02", "hiev07_A03", "hiev07_A04", "hiev07_A05", "hiev07_A06", "hiev07_A07", "hiev07_A08", "hiev07_A09", "hiev07_A10", "hiev07_A11", "hiev07_A12", "hiev07_A13", "hiev07_A14"], "cgs_b": []},
		{"thumb_a": "hiev08_A01S", "thumb_b": "", "cgs_a": ["hiev08_A01", "hiev08_A02", "hiev08_A03", "hiev08_A04", "hiev08_A05"], "cgs_b": []},
		{"thumb_a": "hiev09_A01S", "thumb_b": "", "cgs_a": ["hiev09_A01", "hiev09_A02", "hiev09_A03", "hiev09_A04", "hiev09_A05", "hiev09_A06", "hiev09_A07", "hiev09_A08", "hiev09_A09", "hiev09_A10", "hiev09_A11", "hiev09_A12"], "cgs_b": []},
		{"thumb_a": "hiev10_A01S", "thumb_b": "", "cgs_a": ["hiev10_A01", "hiev10_A02", "hiev10_A03", "hiev10_A04", "hiev10_A05", "hiev10_A06", "hiev10_A07", "hiev10_A08", "hiev10_A09", "hiev10_A10", "hiev10_A11", "hiev10_A12", "hiev10_A13", "hiev10_A14"], "cgs_b": []},
		{"thumb_a": "hiev11_A01S", "thumb_b": "hiev11_B01S", "cgs_a": ["hiev11_A01", "hiev11_A02", "hiev11_A03", "hiev11_A04", "hiev11_A05", "hiev11_A06", "hiev11_A07", "hiev11_A08", "hiev11_A09", "hiev11_A10", "hiev11_A11", "hiev11_A12"], "cgs_b": ["hiev11_B01", "hiev11_B02", "hiev11_B03", "hiev11_B04", "hiev11_B05", "hiev11_B06", "hiev11_B07", "hiev11_B08", "hiev11_B09", "hiev11_B10", "hiev11_B11", "hiev11_B12"]},
		{"thumb_a": "hiev12_A01S", "thumb_b": "", "cgs_a": ["hiev12_A01", "hiev12_A02", "hiev12_A03", "hiev12_A04", "hiev12_A05", "hiev12_A06", "hiev12_A07", "hiev12_A08"], "cgs_b": []},
		{"thumb_a": "hiev13_A01S", "thumb_b": "", "cgs_a": ["hiev13_A01", "hiev13_A02", "hiev13_A03", "hiev13_A04", "hiev13_A05", "hiev13_A06", "hiev13_A07", "hiev13_A08", "hiev13_A09", "hiev13_A10", "hiev13_A11"], "cgs_b": []},
		{"thumb_a": "hiev14_A01S", "thumb_b": "hiev14_B01S", "cgs_a": ["hiev14_A01", "hiev14_A02", "hiev14_A03", "hiev14_A04", "hiev14_A05", "hiev14_A06", "hiev14_A07", "hiev14_A08"], "cgs_b": ["hiev14_B01", "hiev14_B02", "hiev14_B03", "hiev14_B04", "hiev14_B05", "hiev14_B06", "hiev14_B07", "hiev14_B08"]},
		{"thumb_a": "hiev15_A01S", "thumb_b": "hiev15_B01S", "cgs_a": ["hiev15_A01", "hiev15_A02", "hiev15_A03", "hiev15_A04", "hiev15_A05", "hiev15_A06"], "cgs_b": ["hiev15_B01", "hiev15_B02", "hiev15_B03", "hiev15_B04", "hiev15_B05", "hiev15_B06"]},
		{"thumb_a": "hiev16_A01S", "thumb_b": "hiev16_B01S", "cgs_a": ["hiev16_A01", "hiev16_A02", "hiev16_A03", "hiev16_A04", "hiev16_A05", "hiev16_A06", "hiev16_A07", "hiev16_A08", "hiev16_A09", "hiev16_A10", "hiev16_A11", "hiev16_A12", "hiev16_A13", "hiev16_A14", "hiev16_A15", "hiev16_A16", "hiev16_A17", "hiev16_A18", "hiev16_A19", "hiev16_A20", "hiev16_A21", "hiev16_A22", "hiev16_A23", "hiev16_A24", "hiev16_A25", "hiev16_A26"], "cgs_b": ["hiev16_B01", "hiev16_B02", "hiev16_B03", "hiev16_B04", "hiev16_B05", "hiev16_B06", "hiev16_B07", "hiev16_B08", "hiev16_B09", "hiev16_B10", "hiev16_B11", "hiev16_B12", "hiev16_B13", "hiev16_B14", "hiev16_B15", "hiev16_B16", "hiev16_B17", "hiev16_B18", "hiev16_B19", "hiev16_B20", "hiev16_B21", "hiev16_B22", "hiev16_B23", "hiev16_B24", "hiev16_B25", "hiev16_B26"]},
		{"thumb_a": "hiev17_A01S", "thumb_b": "hiev17_B01S", "cgs_a": ["hiev17_A01", "hiev17_A02"], "cgs_b": ["hiev17_B01", "hiev17_B02"]},
		{"thumb_a": "hiev18_A01S", "thumb_b": "hiev18_B01S", "cgs_a": ["hiev18_A01", "hiev18_A02"], "cgs_b": ["hiev18_B01", "hiev18_B02"]},
	],
	"ri": [
		{"thumb_a": "riev01_A01S", "thumb_b": "", "cgs_a": ["riev01_A01", "riev01_A02"], "cgs_b": []},
		{"thumb_a": "riev02_A01S", "thumb_b": "", "cgs_a": ["riev02_A01", "riev02_A02", "riev02_A03"], "cgs_b": []},
		{"thumb_a": "riev03_A01S", "thumb_b": "", "cgs_a": ["riev03_A01", "riev03_A02", "riev03_A03"], "cgs_b": []},
		{"thumb_a": "riev04_A01S", "thumb_b": "riev04_B01S", "cgs_a": ["riev04_A01", "riev04_A02"], "cgs_b": ["riev04_B01", "riev04_B02"]},
		{"thumb_a": "riev05_A01S", "thumb_b": "riev05_B01S", "cgs_a": ["riev05_A01", "riev05_A02"], "cgs_b": ["riev05_B01", "riev05_B02"]},
		{"thumb_a": "riev06_A01S", "thumb_b": "riev06_B01S", "cgs_a": ["riev06_A01", "riev06_A02", "riev06_A03", "riev06_A04", "riev06_A05", "riev06_A06"], "cgs_b": ["riev06_B01", "riev06_B02", "riev06_B03", "riev06_B04", "riev06_B05", "riev06_B06"]},
		{"thumb_a": "riev07_A01S", "thumb_b": "riev07_B01S", "cgs_a": ["riev07_A01", "riev07_A02", "riev07_A03"], "cgs_b": ["riev07_B01", "riev07_B02", "riev07_B03"]},
		{"thumb_a": "riev08_A01S", "thumb_b": "riev08_B01S", "cgs_a": ["riev08_A01", "riev08_A02"], "cgs_b": ["riev08_B01", "riev08_B02"]},
		{"thumb_a": "riev09_A01S", "thumb_b": "", "cgs_a": ["riev09_A01", "riev09_A02", "riev09_A03", "riev09_A04", "riev09_A05", "riev09_A06"], "cgs_b": []},
		{"thumb_a": "riev10_A01S", "thumb_b": "", "cgs_a": ["riev10_A01", "riev10_A02", "riev10_A03", "riev10_A04", "riev10_A05", "riev10_A06", "riev10_A07", "riev10_A08", "riev10_A09", "riev10_A10", "riev10_A11", "riev10_A12", "riev10_A13", "riev10_A14"], "cgs_b": []},
		{"thumb_a": "riev11_A01S", "thumb_b": "", "cgs_a": ["riev11_A01", "riev11_A02", "riev11_A03", "riev11_A04", "riev11_A05", "riev11_A06", "riev11_A07", "riev11_A08", "riev11_A09", "riev11_A10", "riev11_A11", "riev11_A12", "riev11_A13", "riev11_A14", "riev11_A15", "riev11_A16", "riev11_A17", "riev11_A18", "riev11_A19", "riev11_A20"], "cgs_b": []},
		{"thumb_a": "riev12_A01S", "thumb_b": "", "cgs_a": ["riev12_A01", "riev12_A02", "riev12_A03", "riev12_A04", "riev12_A05", "riev12_A06", "riev12_A07", "riev12_A08", "riev12_A09", "riev12_A10", "riev12_A11", "riev12_A12", "riev12_A13", "riev12_A14"], "cgs_b": []},
		{"thumb_a": "riev13_A01S", "thumb_b": "", "cgs_a": ["riev13_A01", "riev13_A02", "riev13_A03", "riev13_A04", "riev13_A05", "riev13_A06", "riev13_A07", "riev13_A08", "riev13_A09", "riev13_A10", "riev13_A11", "riev13_A12", "riev13_A13", "riev13_A14", "riev13_A15"], "cgs_b": []},
		{"thumb_a": "riev14_A01S", "thumb_b": "", "cgs_a": ["riev14_A01", "riev14_A02", "riev14_A03", "riev14_A04", "riev14_A05", "riev14_A06", "riev14_A07", "riev14_A08", "riev14_A09", "riev14_A10", "riev14_A11", "riev14_A12", "riev14_A13", "riev14_A14", "riev14_A15", "riev14_A16", "riev14_A17"], "cgs_b": []},
		{"thumb_a": "riev15_A01S", "thumb_b": "riev15_B01S", "cgs_a": ["riev15_A01", "riev15_A02", "riev15_A03", "riev15_A04", "riev15_A05", "riev15_A06", "riev15_A07", "riev15_A08", "riev15_A09", "riev15_A10"], "cgs_b": ["riev15_B01", "riev15_B02", "riev15_B03", "riev15_B04", "riev15_B05", "riev15_B06", "riev15_B07", "riev15_B08", "riev15_B09", "riev15_B10"]},
		{"thumb_a": "riev16_A01S", "thumb_b": "riev16_B01S", "cgs_a": ["riev16_A01", "riev16_A02", "riev16_A03", "riev16_A04", "riev16_A05", "riev16_A06", "riev16_A07", "riev16_A08", "riev16_A09", "riev16_A10", "riev16_A11", "riev16_A12"], "cgs_b": ["riev16_B01", "riev16_B02", "riev16_B03", "riev16_B04", "riev16_B05", "riev16_B06", "riev16_B07", "riev16_B08", "riev16_B09", "riev16_B10", "riev16_B11", "riev16_B12"]},
		{"thumb_a": "riev17_A01S", "thumb_b": "", "cgs_a": ["riev17_A01", "riev17_A02", "riev17_A03", "riev17_A04", "riev17_A05", "riev17_A06", "riev17_A07", "riev17_A08", "riev17_A09", "riev17_A10", "riev17_A11", "riev17_A12", "riev17_A13", "riev17_A14", "riev17_A15"], "cgs_b": []},
		{"thumb_a": "riev18_A01S", "thumb_b": "", "cgs_a": ["riev18_A01", "riev18_A02", "riev18_A03", "riev18_A04", "riev18_A05", "riev18_A06", "riev18_A07", "riev18_A08"], "cgs_b": []},
		{"thumb_a": "riev19_A01S", "thumb_b": "", "cgs_a": ["riev19_A01", "riev19_A02", "riev19_A03", "riev19_A04", "riev19_A05", "riev19_A06", "riev19_A07", "riev19_A08", "riev19_A09", "riev19_A10", "riev19_A11", "riev19_A12", "riev19_A13", "riev19_A14", "riev19_A15", "riev19_A16", "riev19_A17", "riev19_A18", "riev19_A19", "riev19_A20", "riev19_A21", "riev19_A22", "riev19_A23", "riev19_A24", "riev19_A25", "riev19_A26"], "cgs_b": []},
		{"thumb_a": "riev20_A01S", "thumb_b": "riev20_B01S", "cgs_a": ["riev20_A01", "riev20_A02"], "cgs_b": ["riev20_B01", "riev20_B02"]},
		{"thumb_a": "riev21_A01S", "thumb_b": "riev21_B01S", "cgs_a": ["riev21_A01", "riev21_A02", "riev21_A03"], "cgs_b": ["riev21_B01", "riev21_B02", "riev21_B03"]},
		{"thumb_a": "riev22_A01S", "thumb_b": "", "cgs_a": ["riev22_A01"], "cgs_b": []},
	],
	"yu": [
		{"thumb_a": "yuev01_A01S", "thumb_b": "", "cgs_a": ["yuev01_A01", "yuev01_A02", "yuev01_A03"], "cgs_b": []},
		{"thumb_a": "yuev02_A01S", "thumb_b": "", "cgs_a": ["yuev02_A01", "yuev02_A02"], "cgs_b": []},
		{"thumb_a": "yuev03_A01S", "thumb_b": "yuev03_B01S", "cgs_a": ["yuev03_A01", "yuev03_A02", "yuev03_A03", "yuev03_A04", "yuev03_A05", "yuev03_A06"], "cgs_b": ["yuev03_B01", "yuev03_B02", "yuev03_B03", "yuev03_B04", "yuev03_B05", "yuev03_B06"]},
		{"thumb_a": "yuev04_A01S", "thumb_b": "", "cgs_a": ["yuev04_A01", "yuev04_A02", "yuev04_A03"], "cgs_b": []},
		{"thumb_a": "yuev05_A01S", "thumb_b": "", "cgs_a": ["yuev05_A01", "yuev05_A02", "yuev05_A03"], "cgs_b": []},
		{"thumb_a": "yuev06_A01S", "thumb_b": "", "cgs_a": ["yuev06_A01", "yuev06_A02", "yuev06_A03"], "cgs_b": []},
		{"thumb_a": "yuev07_A01S", "thumb_b": "yuev07_B01S", "cgs_a": ["yuev07_A01", "yuev07_A02", "yuev07_A03", "yuev07_A04", "yuev07_A05", "yuev07_A06", "yuev07_A07"], "cgs_b": ["yuev07_B01", "yuev07_B02", "yuev07_B03", "yuev07_B04", "yuev07_B05", "yuev07_B06", "yuev07_B07"]},
		{"thumb_a": "yuev08_A01S", "thumb_b": "yuev08_B01S", "cgs_a": ["yuev08_A01", "yuev08_A02"], "cgs_b": ["yuev08_B01", "yuev08_B02"]},
		{"thumb_a": "yuev09_A01S", "thumb_b": "", "cgs_a": ["yuev09_A01", "yuev09_A02", "yuev09_A03", "yuev09_A04", "yuev09_A05", "yuev09_A06"], "cgs_b": []},
		{"thumb_a": "yuev10_A01S", "thumb_b": "", "cgs_a": ["yuev10_A01", "yuev10_A02", "yuev10_A03", "yuev10_A04", "yuev10_A05", "yuev10_A06", "yuev10_A07", "yuev10_A08", "yuev10_A09", "yuev10_A10", "yuev10_A11", "yuev10_A12", "yuev10_A13", "yuev10_A14"], "cgs_b": []},
		{"thumb_a": "yuev11_A01S", "thumb_b": "", "cgs_a": ["yuev11_A01", "yuev11_A02", "yuev11_A03", "yuev11_A04", "yuev11_A05", "yuev11_A06", "yuev11_A07", "yuev11_A08", "yuev11_A09", "yuev11_A10", "yuev11_A11", "yuev11_A12"], "cgs_b": []},
		{"thumb_a": "yuev12_A01S", "thumb_b": "", "cgs_a": ["yuev12_A01", "yuev12_A02", "yuev12_A03", "yuev12_A04", "yuev12_A05", "yuev12_A06", "yuev12_A07", "yuev12_A08", "yuev12_A09", "yuev12_A10", "yuev12_A11", "yuev12_A12", "yuev12_A13", "yuev12_A14", "yuev12_A15", "yuev12_A16", "yuev12_A17", "yuev12_A18", "yuev12_A19"], "cgs_b": []},
		{"thumb_a": "yuev13_A01S", "thumb_b": "yuev13_B01S", "cgs_a": ["yuev13_A01", "yuev13_A02", "yuev13_A03", "yuev13_A04", "yuev13_A05", "yuev13_A06", "yuev13_A07", "yuev13_A08", "yuev13_A09", "yuev13_A10", "yuev13_A11"], "cgs_b": ["yuev13_B01", "yuev13_B02", "yuev13_B03", "yuev13_B04", "yuev13_B05", "yuev13_B06", "yuev13_B07", "yuev13_B08", "yuev13_B09", "yuev13_B10", "yuev13_B11"]},
		{"thumb_a": "yuev14_A01S", "thumb_b": "yuev14_B01S", "cgs_a": ["yuev14_A01", "yuev14_A02", "yuev14_A03", "yuev14_A04", "yuev14_A05", "yuev14_A06", "yuev14_A07", "yuev14_A08", "yuev14_A09", "yuev14_A10", "yuev14_A11", "yuev14_A12", "yuev14_A13", "yuev14_A14"], "cgs_b": ["yuev14_B01", "yuev14_B02", "yuev14_B03", "yuev14_B04", "yuev14_B05", "yuev14_B06", "yuev14_B07", "yuev14_B08", "yuev14_B09", "yuev14_B10", "yuev14_B11", "yuev14_B12", "yuev14_B13", "yuev14_B14"]},
		{"thumb_a": "yuev15_A01S", "thumb_b": "", "cgs_a": ["yuev15_A01", "yuev15_A02", "yuev15_A03", "yuev15_A04", "yuev15_A05", "yuev15_A06", "yuev15_A07", "yuev15_A08", "yuev15_A09", "yuev15_A10", "yuev15_A11", "yuev15_A12", "yuev15_A13"], "cgs_b": []},
		{"thumb_a": "yuev16_A01S", "thumb_b": "", "cgs_a": ["yuev16_A01", "yuev16_A02", "yuev16_A03", "yuev16_A04", "yuev16_A05", "yuev16_A06", "yuev16_A07", "yuev16_A08", "yuev16_A09", "yuev16_A10", "yuev16_A11", "yuev16_A12", "yuev16_A13"], "cgs_b": []},
		{"thumb_a": "yuev17_A01S", "thumb_b": "yuev17_B01S", "cgs_a": ["yuev17_A01", "yuev17_A02", "yuev17_A03", "yuev17_A04", "yuev17_A05", "yuev17_A06", "yuev17_A07", "yuev17_A08", "yuev17_A09", "yuev17_A10"], "cgs_b": ["yuev17_B01", "yuev17_B02", "yuev17_B03", "yuev17_B04", "yuev17_B05", "yuev17_B06", "yuev17_B07", "yuev17_B08", "yuev17_B09", "yuev17_B10"]},
		{"thumb_a": "yuev18_A01S", "thumb_b": "yuev18_B01S", "cgs_a": ["yuev18_A01", "yuev18_A02", "yuev18_A03", "yuev18_A04", "yuev18_A05", "yuev18_A06", "yuev18_A07", "yuev18_A08", "yuev18_A09"], "cgs_b": ["yuev18_B01", "yuev18_B02", "yuev18_B03", "yuev18_B04", "yuev18_B05", "yuev18_B06", "yuev18_B07", "yuev18_B08", "yuev18_B09"]},
		{"thumb_a": "yuev19_A01S", "thumb_b": "yuev19_B01S", "cgs_a": ["yuev19_A01", "yuev19_A02", "yuev19_A03", "yuev19_A04", "yuev19_A05", "yuev19_A06", "yuev19_A07", "yuev19_A08", "yuev19_A09", "yuev19_A10", "yuev19_A11", "yuev19_A12", "yuev19_A13", "yuev19_A14", "yuev19_A15", "yuev19_A16", "yuev19_A17", "yuev19_A18", "yuev19_A19", "yuev19_A20", "yuev19_A21", "yuev19_A22", "yuev19_A23", "yuev19_A24", "yuev19_A25", "yuev19_A26"], "cgs_b": ["yuev19_B01", "yuev19_B02", "yuev19_B03", "yuev19_B04", "yuev19_B05", "yuev19_B06", "yuev19_B07", "yuev19_B08", "yuev19_B09", "yuev19_B10", "yuev19_B11", "yuev19_B12", "yuev19_B13", "yuev19_B14", "yuev19_B15", "yuev19_B16", "yuev19_B17", "yuev19_B18", "yuev19_B19", "yuev19_B20", "yuev19_B21", "yuev19_B22", "yuev19_B23", "yuev19_B24", "yuev19_B25", "yuev19_B26"]},
		{"thumb_a": "yuev20_A01S", "thumb_b": "", "cgs_a": ["yuev20_A01"], "cgs_b": []},
		{"thumb_a": "yuev21_A01S", "thumb_b": "yuev21_B01S", "cgs_a": ["yuev21_A01"], "cgs_b": ["yuev21_B01"]},
		{"thumb_a": "yuev22_A01S", "thumb_b": "yuev22_B01S", "cgs_a": ["yuev22_A01"], "cgs_b": ["yuev22_B01"]},
	],
	"mi": [
		{"thumb_a": "miev01_A01S", "thumb_b": "", "cgs_a": ["miev01_A01", "miev01_A02"], "cgs_b": []},
		{"thumb_a": "miev02_A01S", "thumb_b": "", "cgs_a": ["miev02_A01"], "cgs_b": []},
		{"thumb_a": "miev03_A01S", "thumb_b": "", "cgs_a": ["miev03_A01", "miev03_A02", "miev03_A03", "miev03_A04", "miev03_A05"], "cgs_b": []},
		{"thumb_a": "miev04_A01S", "thumb_b": "", "cgs_a": ["miev04_A01", "miev04_A02"], "cgs_b": []},
		{"thumb_a": "miev05_A01S", "thumb_b": "", "cgs_a": ["miev05_A01", "miev05_A02", "miev05_A03", "miev05_A04", "miev05_A05", "miev05_A06"], "cgs_b": []},
		{"thumb_a": "miev06_A01S", "thumb_b": "", "cgs_a": ["miev06_A01", "miev06_A02"], "cgs_b": []},
		{"thumb_a": "miev07_A01S", "thumb_b": "", "cgs_a": ["miev07_A01", "miev07_A02", "miev07_A03", "miev07_A04", "miev07_A05", "miev07_A06"], "cgs_b": []},
		{"thumb_a": "miev08_A01S", "thumb_b": "", "cgs_a": ["miev08_A01", "miev08_A02", "miev08_A03", "miev08_A04", "miev08_A05", "miev08_A06", "miev08_A07", "miev08_A08", "miev08_A09", "miev08_A10", "miev08_A11", "miev08_A12", "miev08_A13", "miev08_A14"], "cgs_b": []},
		{"thumb_a": "miev09_A01S", "thumb_b": "", "cgs_a": ["miev09_A01", "miev09_A02", "miev09_A03", "miev09_A04", "miev09_A05", "miev09_A06", "miev09_A07", "miev09_A08", "miev09_A09", "miev09_A10", "miev09_A11"], "cgs_b": []},
		{"thumb_a": "miev10_A01S", "thumb_b": "", "cgs_a": ["miev10_A01", "miev10_A02", "miev10_A03", "miev10_A04", "miev10_A05", "miev10_A06", "miev10_A07", "miev10_A08", "miev10_A09", "miev10_A10", "miev10_A11"], "cgs_b": []},
		{"thumb_a": "miev11_A01S", "thumb_b": "", "cgs_a": ["miev11_A01", "miev11_A02", "miev11_A03", "miev11_A04", "miev11_A05", "miev11_A06", "miev11_A07", "miev11_A08", "miev11_A09", "miev11_A10", "miev11_A11", "miev11_A12", "miev11_A13"], "cgs_b": []},
		{"thumb_a": "miev12_A01S", "thumb_b": "", "cgs_a": ["miev12_A01", "miev12_A02", "miev12_A03", "miev12_A04", "miev12_A05", "miev12_A06", "miev12_A07", "miev12_A08", "miev12_A09", "miev12_A10", "miev12_A11", "miev12_A12", "miev12_A13", "miev12_A14", "miev12_A15"], "cgs_b": []},
		{"thumb_a": "miev13_A01S", "thumb_b": "miev13_B01S", "cgs_a": ["miev13_A01", "miev13_A02", "miev13_A03", "miev13_A04", "miev13_A05", "miev13_A06", "miev13_A07"], "cgs_b": ["miev13_B01", "miev13_B02"]},
		{"thumb_a": "miev14_A01S", "thumb_b": "", "cgs_a": ["miev14_A01", "miev14_A02", "miev14_A03", "miev14_A04", "miev14_A05", "miev14_A06", "miev14_A07", "miev14_A08", "miev14_A09", "miev14_A10", "miev14_A11", "miev14_A12", "miev14_A13", "miev14_A14", "miev14_A15", "miev14_A16", "miev14_A17", "miev14_A18", "miev14_A19", "miev14_A20", "miev14_A21", "miev14_A22", "miev14_A23", "miev14_A24", "miev14_A25", "miev14_A26"], "cgs_b": []},
		{"thumb_a": "miev15_A01S", "thumb_b": "", "cgs_a": ["miev15_A01"], "cgs_b": []},
		{"thumb_a": "miev16_A01S", "thumb_b": "", "cgs_a": ["miev16_A01"], "cgs_b": []},
	],
}

# 自动从 setupforgallery 提取的 4 女主回想（RECOLLECTION）槽位表
const GALLERY_RECOLL_SLOTS: Dictionary = {
	"hi": [
		{"thumb_a": "hiev09_A01S", "thumb_b": "", "script": "R_HIMARI_H1"},
		{"thumb_a": "hiev12_A01S", "thumb_b": "", "script": "R_HIMARI_H2"},
		{"thumb_a": "hiev11_A01S", "thumb_b": "hiev11_B01S", "script": "R_HIMARI_H3"},
		{"thumb_a": "hiev14_A01S", "thumb_b": "hiev14_B01S", "script": "R_HIMARI_H4"},
	],
	"ri": [
		{"thumb_a": "riev11_A01S", "thumb_b": "", "script": "R_RINA_H1"},
		{"thumb_a": "riev13_A01S", "thumb_b": "", "script": "R_RINA_H2"},
		{"thumb_a": "riev15_A01S", "thumb_b": "riev15_B01S", "script": "R_RINA_H3"},
		{"thumb_a": "riev17_A01S", "thumb_b": "", "script": "R_RINA_H4"},
		{"thumb_a": "riev18_A01S", "thumb_b": "", "script": "R_RINA_H5"},
	],
	"yu": [
		{"thumb_a": "yuev11_A01S", "thumb_b": "", "script": "R_YUZUYU_H1"},
		{"thumb_a": "yuev13_A01S", "thumb_b": "yuev13_B01S", "script": "R_YUZUYU_H2"},
		{"thumb_a": "yuev15_A01S", "thumb_b": "", "script": "R_YUZUYU_H3"},
		{"thumb_a": "yuev17_A01S", "thumb_b": "yuev17_B01S", "script": "R_YUZUYU_H4"},
	],
	"mi": [
		{"thumb_a": "miev09_A01S", "thumb_b": "", "script": "R_MISAKI_H1"},
		{"thumb_a": "miev11_A01S", "thumb_b": "", "script": "R_MISAKI_H2"},
		{"thumb_a": "miev13_A01S", "thumb_b": "miev13_B01S", "script": "R_MISAKI_H3"},
	],
}

var _theme = null
var _vfs: BgiVfs
var _bp_vm: BgiBpVm = null
var _font: Font = null

var _bg_rect: TextureRect
var _cg_grid: Control
var _char_buttons: Array[Button] = []
var _bgm_buttons: Array[Button] = []
var _bgm_fallback_lbl: Label
var _btn_op: Button
var _btn_app_default: Button
var _btn_app_changed: Button

var _viewer_overlay: Control
var _viewer_tex: TextureRect
var _viewer_info: Label

var _current_char_idx: int = 0
var _appearance_mode: int = 0 # 0: 默认外观 (外見デフォルト), 1: 变更外观 (外見変更)
var _current_cg_list: Array = []
var _viewer_idx: int = -1
var _current_bgm_idx: int = 0
var _thumb_cache: Dictionary = {}


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build_ui()


func setup(theme_loader, vfs: BgiVfs, font: Font = null) -> void:
	_theme = theme_loader
	_vfs = vfs
	_font = font
	if _theme != null:
		var bg_t: ImageTexture = _theme.get_tex("sggallery990000")
		if bg_t != null:
			_bg_rect.texture = bg_t
			# 从背景 x=420 处垂直采样薰衣草色渐变，无缝遮盖原盘烘焙的「CG・回想 & 音楽鑑賞」
			var mask_tr := get_node_or_null("TitleMask") as TextureRect
			var bg_img := bg_t.get_image()
			if mask_tr != null and bg_img != null and bg_img.get_width() > 430 and bg_img.get_height() >= 80:
				var strip := bg_img.get_region(Rect2i(420, 14, 16, 66))
				mask_tr.texture = ImageTexture.create_from_image(strip)
	_update_bgm_telop(_current_bgm_idx)


func set_bp_vm(bp_vm: BgiBpVm) -> void:
	_bp_vm = bp_vm


func select_char(idx: int) -> void:
	_select_char(idx)


func open_gallery(has_movie: bool = true) -> void:
	if _btn_op != null:
		_btn_op.visible = has_movie
	_update_appearance_buttons()
	_select_char(_current_char_idx)
	_update_bgm_telop(_current_bgm_idx)
	visible = true


func set_appearance_mode(mode: int) -> void:
	_appearance_mode = clampi(mode, 0, 1)
	_update_appearance_buttons()
	_select_char(_current_char_idx)


func _build_ui() -> void:
	_bg_rect = TextureRect.new()
	_bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg_rect.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(_bg_rect)

	var fallback_bg := ColorRect.new()
	fallback_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	fallback_bg.color = Color(0.68, 0.84, 0.98, 1.0)
	fallback_bg.show_behind_parent = true
	_bg_rect.add_child(fallback_bg)

	# 1. 遮盖左上角烘焙的日文/繁体「CG・回想 & 音楽鑑賞」并绘制简体中文「CG・回想 & 音乐鉴赏」
	var title_mask := TextureRect.new()
	title_mask.name = "TitleMask"
	title_mask.position = Vector2(20, 14)
	title_mask.size = Vector2(396, 66)
	title_mask.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title_mask.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(title_mask)

	var title_lbl := Label.new()
	title_lbl.position = Vector2(30, 18)
	title_lbl.size = Vector2(386, 58)
	title_lbl.text = "CG・回想 & 音乐鉴赏"
	title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 34)
	title_lbl.add_theme_color_override("font_color", Color.WHITE)
	title_lbl.add_theme_color_override("font_outline_color", Color(0.04, 0.08, 0.42, 1.0))
	title_lbl.add_theme_constant_override("outline_size", 10)
	add_child(title_lbl)

	# 2. 右上角按钮：播放 OP + 默认外观 (717,37) + 变更外观 (887,37) + 返 回 (1067,37)，尺寸与原盘 166x46 严格对齐
	_btn_op = _make_glossy_btn("播放 OP", false)
	_btn_op.name = "BtnPlayOp"
	_btn_op.position = Vector2(547, 37)
	_btn_op.size = Vector2(156, 46)
	_btn_op.pressed.connect(func() -> void: play_op_requested.emit())
	add_child(_btn_op)

	_btn_app_default = _make_glossy_btn("默认外观", true)
	_btn_app_default.name = "BtnAppDefault"
	_btn_app_default.position = Vector2(717, 37)
	_btn_app_default.size = Vector2(166, 46)
	_btn_app_default.pressed.connect(func() -> void: set_appearance_mode(0))
	add_child(_btn_app_default)

	_btn_app_changed = _make_glossy_btn("变更外观", false)
	_btn_app_changed.name = "BtnAppChanged"
	_btn_app_changed.position = Vector2(887, 37)
	_btn_app_changed.size = Vector2(166, 46)
	_btn_app_changed.pressed.connect(func() -> void: set_appearance_mode(1))
	add_child(_btn_app_changed)

	var btn_back := _make_glossy_btn("返  回", false)
	btn_back.name = "BtnGalleryBack"
	btn_back.position = Vector2(1067, 37)
	btn_back.size = Vector2(166, 46)
	btn_back.pressed.connect(func() -> void:
		visible = false
		close_requested.emit()
	)
	add_child(btn_back)

	# 3. 中部 7x4 CG MODE + RECOLLECTION 容器 (x=50, y=104, 1180x390)
	_cg_grid = Control.new()
	_cg_grid.name = "CgGrid"
	_cg_grid.position = Vector2(50, 104)
	_cg_grid.size = Vector2(1180, 390)
	add_child(_cg_grid)

	# 4. 4 名女主切换标签栏（与原盘 sggallery990000 坐标 (47+i*170, 507, 166x46) 精确重合，保留日文人名）
	_char_buttons.clear()
	for i in range(CHAR_TABS.size()):
		var cb := _make_glossy_btn(str(CHAR_TABS[i]["name"]), i == 0)
		cb.name = "CharTab_%d" % i
		cb.position = Vector2(47 + i * 170, 507)
		cb.size = Vector2(166, 46)
		var idx := i
		cb.pressed.connect(func() -> void: _select_char(idx))
		add_child(cb)
		_char_buttons.append(cb)

	# 5. 底部 27 首 BGM 按钮（精确对齐原盘 40x40 格位：(50 + col*50, 590 + row*50)）
	_bgm_buttons.clear()
	for i in range(BGM_COUNT):
		var row := i / 14
		var col := i % 14
		var bb := _make_glossy_btn("%d" % [i + 1], i == 0)
		bb.name = "BgmBtn_%d" % i
		bb.position = Vector2(50 + col * 50, 590 + row * 50)
		bb.size = Vector2(40, 40)
		var idx := i
		bb.pressed.connect(func() -> void: _play_bgm(idx))
		add_child(bb)
		_bgm_buttons.append(bb)

	# 右下角蓝色曲名栏（精确覆盖原盘 x=760, y=591, 470x35 曲名栏）
	var telop_box := Panel.new()
	telop_box.position = Vector2(758, 589)
	telop_box.size = Vector2(474, 39)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.04, 0.56, 0.96, 1.0)
	st.border_color = Color(0.02, 0.32, 0.75, 1.0)
	st.set_border_width_all(2)
	st.set_corner_radius_all(8)
	telop_box.add_theme_stylebox_override("panel", st)
	add_child(telop_box)

	_bgm_fallback_lbl = Label.new()
	_bgm_fallback_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bgm_fallback_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bgm_fallback_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_bgm_fallback_lbl.add_theme_font_size_override("font_size", 20)
	_bgm_fallback_lbl.add_theme_color_override("font_color", Color.WHITE)
	_bgm_fallback_lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.18, 0.45, 0.95))
	_bgm_fallback_lbl.add_theme_constant_override("outline_size", 4)
	telop_box.add_child(_bgm_fallback_lbl)

	# 4 个音乐播放控制按钮（精确对齐原盘 x=760+i*120, y=640, 110x40）
	var btn_prev_bgm := _make_glossy_btn("◀◀", false)
	btn_prev_bgm.position = Vector2(760, 640)
	btn_prev_bgm.size = Vector2(110, 40)
	btn_prev_bgm.pressed.connect(func() -> void: _play_bgm((_current_bgm_idx - 1 + BGM_COUNT) % BGM_COUNT))
	add_child(btn_prev_bgm)

	var btn_play_bgm := _make_glossy_btn("▶", true)
	btn_play_bgm.position = Vector2(880, 640)
	btn_play_bgm.size = Vector2(110, 40)
	btn_play_bgm.pressed.connect(func() -> void: _play_bgm(_current_bgm_idx))
	add_child(btn_play_bgm)

	var btn_stop_bgm := _make_glossy_btn("■", false)
	btn_stop_bgm.position = Vector2(1000, 640)
	btn_stop_bgm.size = Vector2(110, 40)
	btn_stop_bgm.pressed.connect(func() -> void: stop_bgm_requested.emit())
	add_child(btn_stop_bgm)

	var btn_next_bgm := _make_glossy_btn("▶▶", false)
	btn_next_bgm.position = Vector2(1120, 640)
	btn_next_bgm.size = Vector2(110, 40)
	btn_next_bgm.pressed.connect(func() -> void: _play_bgm((_current_bgm_idx + 1) % BGM_COUNT))
	add_child(btn_next_bgm)

	# 6. 全屏 CG 鉴赏查看器
	_viewer_overlay = Control.new()
	_viewer_overlay.name = "CgViewerOverlay"
	_viewer_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewer_overlay.visible = false
	add_child(_viewer_overlay)

	var vbg := ColorRect.new()
	vbg.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbg.color = Color(0, 0, 0, 0.96)
	_viewer_overlay.add_child(vbg)

	_viewer_tex = TextureRect.new()
	_viewer_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewer_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_viewer_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_viewer_overlay.add_child(_viewer_tex)

	_viewer_info = Label.new()
	_viewer_info.position = Vector2(20, 16)
	_viewer_info.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_viewer_info.add_theme_font_size_override("font_size", 19)
	_viewer_overlay.add_child(_viewer_info)

	_viewer_overlay.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			if ev.button_index == MOUSE_BUTTON_RIGHT:
				_viewer_overlay.visible = false
			elif ev.button_index == MOUSE_BUTTON_LEFT:
				if _current_cg_list.is_empty() or _viewer_idx + 1 >= _current_cg_list.size():
					_viewer_overlay.visible = false
				else:
					_open_cg_viewer(_viewer_idx + 1)
	)


func _make_glossy_btn(txt: String, active: bool) -> Button:
	var b := Button.new()
	b.text = txt
	b.add_theme_font_size_override("font_size", 19)
	_apply_glossy_style(b, active)
	return b


func _apply_glossy_style(b: Button, active: bool) -> void:
	if b == null:
		return
	var sb_n := StyleBoxFlat.new()
	sb_n.set_border_width_all(2)
	sb_n.set_corner_radius_all(8)
	if active:
		sb_n.bg_color = Color(0.06, 0.58, 0.96, 1.0)
		sb_n.border_color = Color(0.02, 0.35, 0.78, 1.0)
		b.add_theme_color_override("font_color", Color.WHITE)
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.add_theme_color_override("font_pressed_color", Color.WHITE)
		b.add_theme_color_override("font_outline_color", Color(0.02, 0.18, 0.45, 0.95))
		b.add_theme_constant_override("outline_size", 4)
	else:
		sb_n.bg_color = Color(0.95, 0.95, 0.94, 1.0)
		sb_n.border_color = Color(0.75, 0.76, 0.78, 1.0)
		b.add_theme_color_override("font_color", Color(0.44, 0.43, 0.43, 1.0))
		b.add_theme_color_override("font_hover_color", Color(0.06, 0.48, 0.88, 1.0))
		b.add_theme_color_override("font_pressed_color", Color.WHITE)
		b.add_theme_constant_override("outline_size", 0)
	var sb_h := sb_n.duplicate() as StyleBoxFlat
	sb_h.bg_color = Color(0.18, 0.68, 1.0, 1.0)
	b.add_theme_stylebox_override("normal", sb_n)
	b.add_theme_stylebox_override("hover", sb_h)
	b.add_theme_stylebox_override("pressed", sb_h)


func _update_appearance_buttons() -> void:
	_apply_glossy_style(_btn_app_default, _appearance_mode == 0)
	_apply_glossy_style(_btn_app_changed, _appearance_mode == 1)


func _select_char(idx: int) -> void:
	_current_char_idx = clampi(idx, 0, CHAR_TABS.size() - 1)
	for i in range(_char_buttons.size()):
		_apply_glossy_style(_char_buttons[i], i == _current_char_idx)
	_render_cg_page()


func _render_cg_page() -> void:
	for c in _cg_grid.get_children():
		c.queue_free()
	var cat_key: String = str(CHAR_TABS[_current_char_idx]["key"])
	var cg_slots: Array = GALLERY_CG_SLOTS.get(cat_key, [])
	_current_cg_list = []

	# 1. CG MODE 7 列 x 4 行缩略图 (每格 160x90, 间距 10px -> 步长 170x100)
	for s_idx in range(cg_slots.size()):
		var slot: Dictionary = cg_slots[s_idx]
		var col := s_idx % 7
		var row := s_idx / 7
		var use_b := (_appearance_mode == 1) and not str(slot.get("thumb_b", "")).is_empty()
		var thumb_name := str(slot["thumb_b"]) if use_b else str(slot["thumb_a"])
		var seq: Array = slot["cgs_b"] if (use_b and not (slot["cgs_b"] as Array).is_empty()) else slot["cgs_a"]
		if s_idx == 0:
			_current_cg_list = seq.duplicate()

		var btn := _make_thumb_btn(thumb_name)
		btn.name = "CgSlot_%d" % s_idx
		btn.position = Vector2(col * 170, row * 98)
		btn.size = Vector2(160, 90)
		var seq_copy := seq.duplicate()
		btn.pressed.connect(func() -> void:
			_current_cg_list = seq_copy
			_open_cg_viewer(0)
		)
		_cg_grid.add_child(btn)

	# 2. RECOLLECTION 回想模式缩略图（位于第 4 行 row=3 右侧对齐）
	var recoll_slots: Array = GALLERY_RECOLL_SLOTS.get(cat_key, [])
	var r_count := recoll_slots.size()
	for r_idx in range(r_count):
		var rslot: Dictionary = recoll_slots[r_idx]
		var col := (7 - r_count) + r_idx
		var row := 3
		var use_b := (_appearance_mode == 1) and not str(rslot.get("thumb_b", "")).is_empty()
		var thumb_name := str(rslot["thumb_b"]) if use_b else str(rslot["thumb_a"])
		var sc_name := str(rslot.get("script", ""))

		var rbtn := _make_thumb_btn(thumb_name)
		rbtn.name = "RecollSlot_%d" % r_idx
		rbtn.position = Vector2(col * 170, row * 98)
		rbtn.size = Vector2(160, 90)
		var sc_copy := sc_name
		var app_copy := _appearance_mode
		rbtn.pressed.connect(func() -> void:
			if not sc_copy.is_empty():
				visible = false
				recollection_requested.emit(sc_copy, app_copy)
		)
		_cg_grid.add_child(rbtn)


func _make_thumb_btn(thumb_name: String) -> TextureButton:
	var btn := TextureButton.new()
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_SCALE
	var frames := _get_thumb_frames(thumb_name)
	if frames.size() >= 1:
		btn.texture_normal = frames[0] as Texture2D
	if frames.size() >= 2:
		btn.texture_hover = frames[1] as Texture2D
	if frames.size() >= 3:
		btn.texture_pressed = frames[2] as Texture2D
	return btn


func _get_thumb_frames(thumb_name: String) -> Array:
	if thumb_name.is_empty():
		return []
	if _thumb_cache.has(thumb_name):
		var cached = _thumb_cache[thumb_name]
		if cached is Array:
			return cached
		return [cached]
	if _vfs == null or not _vfs.has_entry(thumb_name):
		return []
	var img := _vfs.decode_image(thumb_name)
	if img == null:
		return []
	var w := img.get_width()
	var h := img.get_height()
	var frames: Array = []
	# BGI 画廊缩略图 *S 为 3 帧水平拼图 (480x90 = Normal | Hover | Pressed 各 160x90)
	if w >= 300 and w % 3 == 0 and float(w) / float(maxi(h, 1)) >= 3.0:
		var fw := w / 3
		for s in range(3):
			var sub_img := img.get_region(Rect2i(s * fw, 0, fw, h))
			frames.append(ImageTexture.create_from_image(sub_img))
	else:
		var tex := ImageTexture.create_from_image(img)
		frames = [tex, tex, tex]
	_thumb_cache[thumb_name] = frames
	return frames


func _get_thumb_tex(thumb_name: String) -> ImageTexture:
	var frames := _get_thumb_frames(thumb_name)
	return (frames[0] as ImageTexture) if not frames.is_empty() else null


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if _viewer_overlay != null and _viewer_overlay.visible:
			if event.keycode == KEY_ESCAPE:
				_viewer_overlay.visible = false
				get_viewport().set_input_as_handled()
			elif event.keycode in [KEY_LEFT, KEY_UP]:
				if _viewer_idx > 0:
					_open_cg_viewer(_viewer_idx - 1)
				get_viewport().set_input_as_handled()
			elif event.keycode in [KEY_RIGHT, KEY_DOWN, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
				if _current_cg_list.is_empty() or _viewer_idx + 1 >= _current_cg_list.size():
					_viewer_overlay.visible = false
				else:
					_open_cg_viewer(_viewer_idx + 1)
				get_viewport().set_input_as_handled()


func _open_cg_viewer(idx: int) -> void:
	if idx < 0 or idx >= _current_cg_list.size() or _vfs == null:
		return
	_viewer_idx = idx
	var raw_name := str(_current_cg_list[idx])
	var cg_name := _bp_vm.resolve_nude_image_name(raw_name) if _bp_vm != null else raw_name
	var img := _vfs.decode_image(cg_name)
	if img != null:
		_viewer_tex.texture = ImageTexture.create_from_image(img)
	var mode_str := "变更外观" if _appearance_mode == 1 else "默认外观"
	_viewer_info.text = "%s (%s) [%d / %d]  （左键/→下一张  ←上一张  右键/Esc关闭）" % [cg_name, mode_str, idx + 1, _current_cg_list.size()]
	_viewer_overlay.visible = true


func _play_bgm(idx: int) -> void:
	_current_bgm_idx = clampi(idx, 0, BGM_COUNT - 1)
	for i in range(_bgm_buttons.size()):
		_apply_glossy_style(_bgm_buttons[i], i == _current_bgm_idx)
	_update_bgm_telop(_current_bgm_idx)
	var bgm_entry := "FL_bgm_%02d" % [_current_bgm_idx + 1]
	play_bgm_requested.emit(bgm_entry)


func _update_bgm_telop(idx: int) -> void:
	if _bgm_fallback_lbl != null and idx >= 0 and idx < BGM_TITLES_ZH.size():
		_bgm_fallback_lbl.text = BGM_TITLES_ZH[idx]
		_bgm_fallback_lbl.visible = true
