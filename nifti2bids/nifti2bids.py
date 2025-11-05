#!/usr/bin/env python3
import argparse
import shutil
import sys
from pathlib import Path

# command format:
# python src/nifti2bids/convert_to_bids.py --src-dir "/ibmgpfs/cuizaixu_lab/xuhaoshu/cuilab_folder/BP_QC_folder/raw_data/NIFTI/THU_20240830_EFI_055_ZRL" --src-list "e:\\projects\\neuroimg_pipeline\\src\\nifti2bids\\THU_20240830_EFI_055_ZRL.txt" --out-dir "E:\\BIDS_output\\THU_20240830_EFI_055_ZRL" --subject EFI055ZRL

def parse_args():
    p = argparse.ArgumentParser(
        description=(
            "将原始 NIFTI 文件按 BIDS 命名复制到目标目录。"
        )
    )
    p.add_argument(
        "--src-dir",
        required=True,
        help="原始 NIFTI 文件所在目录（包含 .nii.gz/.json/.bval/.bvec）。",
    )
    p.add_argument(
        "--src-list",
        required=False,
        help=(
            "可选：文本文件，包含需要处理的文件名列表（一行一个，基于 src-dir 的相对文件名）。"
        ),
    )
    p.add_argument(
        "--subject",
        required=False,
        help=(
            "BIDS subject 标签（例如 EFI055ZRL）。默认从 src-dir 目录名推断。"
        ),
    )
    p.add_argument(
        "--out-dir",
        required=True,
        help="输出根目录（将在其中创建 anat/dwi/fmap/func 子目录）。",
    )
    p.add_argument(
        "--dry-run",
        action="store_true",
        help="仅显示计划复制的文件，不实际复制。",
    )
    return p.parse_args()


def read_src_list(src_list_path: Path):
    items = []
    with src_list_path.open("r", encoding="utf-8") as f:
        for line in f:
            s = line.strip()
            if not s:
                continue
            # 过滤树形输出中可能包含的前缀/符号
            s = s.replace("│", "").replace("├", "").replace("└", "").strip()
            items.append(s)
    return items


def series_num_from_name(name: str):
    base = name
    if "." in base:
        base = base.split(".")[0]
    parts = base.split("_")
    if not parts:
        return None
    try:
        return int(parts[-1])
    except Exception:
        return None


def is_nii_name(name: str) -> bool:
    n = name.lower()
    return n.endswith(".nii") or n.endswith(".nii.gz")


def ensure_dirs(root: Path):
    for d in ["anat", "dwi", "fmap", "func"]:
        (root / d).mkdir(parents=True, exist_ok=True)


def default_subject_from_src_dir(src_dir: Path):
    name = src_dir.name
    # 例如 THU_20240830_EFI_055_ZRL -> EFI055ZRL
    if "EFI_" in name:
        idx = name.index("EFI_")
        cand = name[idx:]
        return cand.replace("_", "")
    return name.replace("_", "")


def copy_or_print(src: Path, dst: Path, dry_run: bool):
    action = "COPY" if not dry_run else "PLAN"
    print(f"[{action}] {src} -> {dst}")
    if not dry_run:
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)


def find_pair(src_dir: Path, base: str, exts):
    found = {}
    for ext in exts:
        p = src_dir / f"{base}.{ext}"
        if p.exists():
            found[ext] = p
    return found


def main():
    args = parse_args()
    src_dir = Path(args.src_dir)
    out_dir = Path(args.out_dir)
    if not src_dir.exists():
        print(f"ERROR: src-dir 不存在: {src_dir}")
        sys.exit(1)

    subject = args.subject or default_subject_from_src_dir(src_dir)
    ensure_dirs(out_dir)

    # 获取候选文件名列表（基于 src-dir）
    if args.src_list:
        src_list = read_src_list(Path(args.src_list))
        # 仅保留存在的文件
        files = [src_dir / x for x in src_list if (src_dir / x).exists()]
        missing = [x for x in src_list if not (src_dir / x).exists()]
        if missing:
            print(f"WARN: 列表中有 {len(missing)} 个文件在 src-dir 未找到，已忽略。")
    else:
        files = list(src_dir.glob("*"))

    basenames = [f.name for f in files]

    # 分类与选择逻辑
    # 1) ANAT
    # 兼容大小写与 .nii/.nii.gz 两种扩展名
    t1_candidates = [
        b for b in basenames
        if ("t1" in b.lower() and "mprage" in b.lower() and is_nii_name(b))
    ]
    t2_candidates = [
        b for b in basenames
        if ("t2" in b.lower() and "spc" in b.lower() and is_nii_name(b))
    ]

    t1_pick = None
    if t1_candidates:
        # 优先选择 series 最小的作为 run-1
        t1_pick = sorted(t1_candidates, key=lambda x: (series_num_from_name(x) or 9999))[0]
        t1_base = t1_pick.split(".")[0]
        # 支持 .nii 或 .nii.gz 任意一种
        t1_pair = find_pair(src_dir, t1_base, ["nii.gz", "nii", "json"])
        for ext, src in t1_pair.items():
            dst = out_dir / "anat" / f"sub-{subject}_run-1_T1w.{ext}"
            copy_or_print(src, dst, args.dry_run)

    if t2_candidates:
        t2_pick = sorted(t2_candidates, key=lambda x: (series_num_from_name(x) or 9999))[0]
        t2_base = t2_pick.split(".")[0]
        t2_pair = find_pair(src_dir, t2_base, ["nii.gz", "nii", "json"])
        for ext, src in t2_pair.items():
            dst = out_dir / "anat" / f"sub-{subject}_T2w.{ext}"
            copy_or_print(src, dst, args.dry_run)

    # 2) DWI 本体（PA）
    dwi_pa_nii = [b for b in basenames if ("sms4_diff_CMR130_PA" in b and b.endswith(".nii.gz"))]
    dwi_pa_series = {}
    for b in dwi_pa_nii:
        s = series_num_from_name(b)
        if s is not None:
            dwi_pa_series.setdefault(s, {})
            base = b.split(".")[0]
            dwi_pa_series[s]["nii.gz"] = src_dir / b
            # 匹配同 series 的 bval/bvec/json
            for ext in ["bval", "bvec", "json"]:
                p = src_dir / f"{base}.{ext}"
                if p.exists():
                    dwi_pa_series[s][ext] = p

    pick_series = None
    # 优先 8 > 6 > 最大
    for preferred in [8, 6]:
        if preferred in dwi_pa_series and ("bval" in dwi_pa_series[preferred]) and ("bvec" in dwi_pa_series[preferred]):
            pick_series = preferred
            break
    if pick_series is None and dwi_pa_series:
        # 选择拥有 bval/bvec 的最大 series
        available = [s for s, m in dwi_pa_series.items() if "bval" in m and "bvec" in m]
        if available:
            pick_series = sorted(available)[-1]

    if pick_series is not None:
        m = dwi_pa_series[pick_series]
        for ext, src in m.items():
            dst = out_dir / "dwi" / f"sub-{subject}_dir-PA_dwi.{ext}"
            copy_or_print(src, dst, args.dry_run)

    # 3) FMAP for DWI (AP B0)
    dwi_b0_ap_nii = [b for b in basenames if ("sms4_diff_CMR130_B0_AP" in b and b.endswith(".nii.gz"))]
    if dwi_b0_ap_nii:
        b = sorted(dwi_b0_ap_nii, key=lambda x: (series_num_from_name(x) or 0))[-1]
        base = b.split(".")[0]
        pair = find_pair(src_dir, base, ["nii.gz", "json"])
        for ext, src in pair.items():
            dst = out_dir / "fmap" / f"sub-{subject}_acq-dwi_dir-AP_epi.{ext}"
            copy_or_print(src, dst, args.dry_run)

    # 4) FMAP for BOLD (REST/TASK; AP/PA)
    def pick_fmap(direction: str, kind: str):
        # direction in {"AP","PA"}, kind in {"REST","TASK1","TASK2"}
        cand = [b for b in basenames if (f"ep2d_se_2mm_{direction}_{kind}" in b and b.endswith(".nii.gz"))]
        if not cand:
            return None
        b = sorted(cand, key=lambda x: (series_num_from_name(x) or 0))[-1]
        base = b.split(".")[0]
        return find_pair(src_dir, base, ["nii.gz", "json"])

    # REST AP/PA
    rest_ap = pick_fmap("AP", "REST")
    rest_pa = pick_fmap("PA", "REST")
    if rest_ap:
        for ext, src in rest_ap.items():
            dst = out_dir / "fmap" / f"sub-{subject}_dir-AP_acq-rest_epi.{ext}"
            copy_or_print(src, dst, args.dry_run)
    if rest_pa:
        for ext, src in rest_pa.items():
            dst = out_dir / "fmap" / f"sub-{subject}_dir-PA_acq-rest_epi.{ext}"
            copy_or_print(src, dst, args.dry_run)

    # TASK AP/PA：优先 TASK1，没有再用 TASK2
    task_ap = pick_fmap("AP", "TASK1") or pick_fmap("AP", "TASK2")
    task_pa = pick_fmap("PA", "TASK1") or pick_fmap("PA", "TASK2")
    if task_ap:
        for ext, src in task_ap.items():
            dst = out_dir / "fmap" / f"sub-{subject}_dir-AP_acq-task_epi.{ext}"
            copy_or_print(src, dst, args.dry_run)
    if task_pa:
        for ext, src in task_pa.items():
            dst = out_dir / "fmap" / f"sub-{subject}_dir-PA_acq-task_epi.{ext}"
            copy_or_print(src, dst, args.dry_run)

    # 5) FUNC BOLD
    task_map = {
        "fm": "sms4_bold_fm",
        "math": "sms4_bold_math",
        "natural": "sms4_bold_natural",
        "nback": "sms4_bold_nback",
        "read": "sms4_bold_read",
        "sst": "sms4_bold_sst",
        "switch": "sms4_bold_switch",
    }

    # REST 1/2
    rest1 = [b for b in basenames if ("sms4_bold_rest1" in b and b.endswith(".nii.gz"))]
    rest2 = [b for b in basenames if ("sms4_bold_rest2" in b and b.endswith(".nii.gz"))]
    if rest1:
        b = sorted(rest1, key=lambda x: (series_num_from_name(x) or 0))[0]
        base = b.split(".")[0]
        pair = find_pair(src_dir, base, ["nii.gz", "json"])
        for ext, src in pair.items():
            dst = out_dir / "func" / f"sub-{subject}_task-rest_run-1_bold.{ext}"
            copy_or_print(src, dst, args.dry_run)
    if rest2:
        b = sorted(rest2, key=lambda x: (series_num_from_name(x) or 0))[0]
        base = b.split(".")[0]
        pair = find_pair(src_dir, base, ["nii.gz", "json"])
        for ext, src in pair.items():
            dst = out_dir / "func" / f"sub-{subject}_task-rest_run-2_bold.{ext}"
            copy_or_print(src, dst, args.dry_run)

    # 其他任务：若同任务有多次采集，则按 series 号排序并赋 run-1, run-2...
    for task, token in task_map.items():
        bolds = [b for b in basenames if (token in b and b.endswith(".nii.gz"))]
        if not bolds:
            continue
        bolds_sorted = sorted(bolds, key=lambda x: (series_num_from_name(x) or 0))
        for idx, b in enumerate(bolds_sorted, start=1):
            base = b.split(".")[0]
            pair = find_pair(src_dir, base, ["nii.gz", "json"])
            run_suffix = f"_run-{idx}" if len(bolds_sorted) > 1 else ""
            for ext, src in pair.items():
                dst = out_dir / "func" / f"sub-{subject}_task-{task}{run_suffix}_bold.{ext}"
                copy_or_print(src, dst, args.dry_run)

    print("完成。")


if __name__ == "__main__":
    main()