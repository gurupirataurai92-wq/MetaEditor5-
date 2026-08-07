<?php
/**
 * Photo uploads.
 *
 * Every uploaded file is checked before it is kept: size, that PHP itself
 * received it as an upload, that it really is an image, and that its type is
 * one we allow. It is then re-encoded through GD, which drops anything hidden
 * inside the original file, and saved under a generated name. Whatever the
 * visitor called the file is never used as a path.
 */

if (!defined('LYMOND')) { http_response_code(403); exit('Forbidden'); }

const ALLOWED_IMAGE_TYPES = [IMAGETYPE_JPEG, IMAGETYPE_PNG, IMAGETYPE_WEBP, IMAGETYPE_GIF];

function upload_error_message(int $code): string
{
    return match ($code) {
        UPLOAD_ERR_INI_SIZE, UPLOAD_ERR_FORM_SIZE => 'that file is larger than the server allows',
        UPLOAD_ERR_PARTIAL                        => 'the upload was interrupted',
        UPLOAD_ERR_NO_FILE                        => 'no file was chosen',
        UPLOAD_ERR_NO_TMP_DIR                     => 'the server has no temporary folder configured',
        UPLOAD_ERR_CANT_WRITE                     => 'the server could not write the file',
        default                                   => 'the upload failed',
    };
}

/**
 * Store one uploaded photo against an item.
 *
 * @return array{0:bool,1:string} success and a message
 */
function store_photo(array $file, string $itemType, int $itemId, string $refPrefix): array
{
    if (!isset($file['error']) || is_array($file['error'])) {
        return [false, 'That upload was malformed.'];
    }
    if ($file['error'] !== UPLOAD_ERR_OK) {
        return [false, 'Photo skipped — ' . upload_error_message((int)$file['error']) . '.'];
    }
    if ($file['size'] > UPLOAD_MAX_BYTES) {
        return [false, '"' . basename($file['name']) . '" is bigger than '
                     . round(UPLOAD_MAX_BYTES / 1048576) . ' MB.'];
    }
    if (!is_uploaded_file($file['tmp_name'])) {
        return [false, 'That file did not arrive as an upload.'];
    }

    $info = @getimagesize($file['tmp_name']);
    if ($info === false || !in_array($info[2], ALLOWED_IMAGE_TYPES, true)) {
        return [false, '"' . basename($file['name']) . '" is not a JPEG, PNG, WebP or GIF image.'];
    }

    $count = (int)q_val('SELECT COUNT(*) FROM photos WHERE item_type = ? AND item_id = ?', [$itemType, $itemId]);
    if ($count >= PHOTOS_PER_ITEM) {
        return [false, 'This item already has the maximum of ' . PHOTOS_PER_ITEM . ' photos.'];
    }

    $src = match ($info[2]) {
        IMAGETYPE_JPEG => @imagecreatefromjpeg($file['tmp_name']),
        IMAGETYPE_PNG  => @imagecreatefrompng($file['tmp_name']),
        IMAGETYPE_WEBP => @imagecreatefromwebp($file['tmp_name']),
        IMAGETYPE_GIF  => @imagecreatefromgif($file['tmp_name']),
        default        => false,
    };
    if (!$src) { return [false, 'That image could not be read.']; }

    /* Shrink to a sensible size for the web. */
    $w = imagesx($src);
    $h = imagesy($src);
    $scale = min(1, PHOTO_MAX_EDGE / max($w, $h));
    $nw = max(1, (int)round($w * $scale));
    $nh = max(1, (int)round($h * $scale));

    $dst = imagecreatetruecolor($nw, $nh);
    imagefill($dst, 0, 0, imagecolorallocate($dst, 255, 255, 255));   // flatten transparency
    imagecopyresampled($dst, $src, 0, 0, 0, 0, $nw, $nh, $w, $h);
    imagedestroy($src);

    if (!is_dir(UPLOAD_DIR) && !@mkdir(UPLOAD_DIR, 0775, true)) {
        imagedestroy($dst);
        return [false, 'The uploads folder does not exist and could not be created.'];
    }
    if (!is_writable(UPLOAD_DIR)) {
        imagedestroy($dst);
        return [false, 'The uploads folder is not writable. Check the permissions on assets/uploads.'];
    }

    $name = $refPrefix . '-' . bin2hex(random_bytes(6)) . '.jpg';
    $ok = imagejpeg($dst, UPLOAD_DIR . '/' . $name, PHOTO_JPEG_QUALITY);
    imagedestroy($dst);
    if (!$ok) { return [false, 'The photo could not be saved to disk.']; }

    $sort = (int)q_val('SELECT COALESCE(MAX(sort_order), 0) + 1 FROM photos WHERE item_type = ? AND item_id = ?',
                       [$itemType, $itemId]);
    q('INSERT INTO photos (item_type, item_id, filename, sort_order) VALUES (?, ?, ?, ?)',
      [$itemType, $itemId, $name, $sort]);

    return [true, $name];
}

/** Handle a whole `<input type="file" multiple>` field. */
function store_photos(string $field, string $itemType, int $itemId, string $refPrefix): array
{
    $messages = [];
    if (empty($_FILES[$field]) || !is_array($_FILES[$field]['name'])) { return $messages; }

    $files = $_FILES[$field];
    $total = count($files['name']);
    for ($i = 0; $i < $total; $i++) {
        if ((int)$files['error'][$i] === UPLOAD_ERR_NO_FILE) { continue; }
        [$ok, $msg] = store_photo([
            'name'     => $files['name'][$i],
            'type'     => $files['type'][$i],
            'tmp_name' => $files['tmp_name'][$i],
            'error'    => $files['error'][$i],
            'size'     => $files['size'][$i],
        ], $itemType, $itemId, $refPrefix);
        if (!$ok) { $messages[] = $msg; }
    }
    return $messages;
}

function delete_photo(int $photoId, string $itemType, int $itemId): bool
{
    $photo = q_one('SELECT * FROM photos WHERE id = ? AND item_type = ? AND item_id = ?',
                   [$photoId, $itemType, $itemId]);
    if (!$photo) { return false; }

    $path = UPLOAD_DIR . '/' . basename($photo['filename']);
    if (is_file($path)) { @unlink($path); }
    q('DELETE FROM photos WHERE id = ?', [$photoId]);
    return true;
}

function delete_photos_for(string $itemType, int $itemId): void
{
    foreach (q_all('SELECT filename FROM photos WHERE item_type = ? AND item_id = ?', [$itemType, $itemId]) as $p) {
        $path = UPLOAD_DIR . '/' . basename($p['filename']);
        if (is_file($path)) { @unlink($path); }
    }
    q('DELETE FROM photos WHERE item_type = ? AND item_id = ?', [$itemType, $itemId]);
}

/** Move a photo to the front so it becomes the cover. */
function make_cover(int $photoId, string $itemType, int $itemId): void
{
    $min = (int)q_val('SELECT COALESCE(MIN(sort_order), 1) FROM photos WHERE item_type = ? AND item_id = ?',
                      [$itemType, $itemId]);
    q('UPDATE photos SET sort_order = ? WHERE id = ? AND item_type = ? AND item_id = ?',
      [$min - 1, $photoId, $itemType, $itemId]);
}

function photos_for(string $itemType, int $itemId): array
{
    return q_all('SELECT * FROM photos WHERE item_type = ? AND item_id = ? ORDER BY sort_order, id',
                 [$itemType, $itemId]);
}
