-- Kabanchiki: payout receipts may be PDFs, not just photos.
--
-- A bank receipt is usually a PDF, and photographing a screen to satisfy the
-- uploader is exactly the kind of friction worth removing. Receipts already
-- live in the task-photos bucket (that is where attach_receipt puts them), so
-- widening that bucket's MIME list is the whole change — no new bucket, no new
-- RLS policies, no moving existing objects.
--
-- The size limit stays at 10 MB: a scanned receipt fits comfortably, and the
-- clients still refuse anything larger before the upload starts.

update storage.buckets
   set allowed_mime_types = array[
       'image/jpeg', 'image/png', 'image/webp', 'application/pdf'
   ]
 where id = 'task-photos';
