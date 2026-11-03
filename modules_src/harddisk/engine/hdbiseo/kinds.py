"""파일 종류 분류."""

IMAGE = {"jpg", "jpeg", "png", "gif", "bmp", "webp", "heic", "heif", "tif", "tiff", "raw", "cr2", "nef", "arw", "dng"}
VIDEO = {"mp4", "mov", "avi", "mkv", "wmv", "m4v", "mts", "m2ts", "3gp", "mpg", "mpeg", "webm", "flv"}
AUDIO = {"mp3", "wav", "m4a", "aac", "flac", "ogg", "wma"}
DOC = {"hwp", "hwpx", "doc", "docx", "xls", "xlsx", "xlsm", "ppt", "pptx", "pdf", "txt", "md", "csv", "rtf", "log"}

KIND_LABELS = {
    "image": "사진",
    "video": "영상",
    "audio": "소리",
    "doc": "문서",
    "other": "기타",
}

DOC_LABELS = {
    "hwp": "한글", "hwpx": "한글", "doc": "워드", "docx": "워드",
    "xls": "엑셀", "xlsx": "엑셀", "xlsm": "엑셀", "ppt": "파워포인트", "pptx": "파워포인트",
    "pdf": "PDF", "txt": "글", "md": "글", "csv": "표", "rtf": "글", "log": "글",
}


def kind_of(ext: str) -> str:
    e = (ext or "").lower()
    if e in IMAGE:
        return "image"
    if e in VIDEO:
        return "video"
    if e in AUDIO:
        return "audio"
    if e in DOC:
        return "doc"
    return "other"
