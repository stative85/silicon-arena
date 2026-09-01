extends RefCounted
class_name ArtifactSaver

const ARCHIVE_DIR: String = "user://ghost_archive"

func ensure_archive_dir() -> int:
    return DirAccess.make_dir_recursive_absolute(ARCHIVE_DIR)

func save_text(file_name: String, text: String) -> String:
    ensure_archive_dir()
    var path := "%s/%s" % [ARCHIVE_DIR, file_name]
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file != null:
        file.store_string(text)
        file.flush()
    return path
