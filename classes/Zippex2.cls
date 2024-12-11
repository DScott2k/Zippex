//Copyright (c) 2024 Pedro Dal Col, Pliny Smith, Daniel Scott
//Drop-in replacement for original Zippex
public class Zippex2
{
    private compression.ZipReader zipReader;
    private compression.ZipWriter zipWriter;

    // Zippex2 constructor
    // Instantiates a new empty Zippex2 object (empty Zip archive).
    public Zippex2()
    {
        zipReader = null;
        zipWriter = new compression.ZipWriter();
        zipWriter.setMethod(compression.Method.STORED);
    }
   
    // Zippex2 UnZipping Constructor
    // Instantiates a new Zippex2 object from an existing Zip archive passed as a Blob
    public Zippex2(Blob fileData)
    {
        zipReader = new compression.ZipReader(fileData);
        zipWriter = null;
    }

    private compression.zipWriter switchToZipWriter() {
        if (zipWriter != null) {
            return this.zipWriter;
        }
        //Convert ZipReader to ZipWriter
        zipWriter = new compression.ZipWriter();
        if (zipReader!=null) {
           for (compression.ZipEntry entry : zipReader.getEntries())
           {
               zipWriter.addEntry(entry);
           }
        }
        zipReader = null;
        return zipWriter;
    }

    //  Returns a set of filenames from the current Zip archive.
    public Set<String> getFileNames()
    {
        if (zipWriter != null) {
            return zipWriter.getEntryNames();
        }
        else
        {
            return new Set<String>(zipReader.getEntryNames());
        }
    }

    //Returns true if current archive contains the specified file
    public Boolean containsFile(String fileName)
    {
        return getFileNames().contains(fileName);
    }

    public static void unzipAttachment(Id srcAttId, Id destObjId, String[] fileNames, Boolean attemptAsync)
    {
        try 
        {
            if (attemptAsync && !System.isFuture() && !System.isBatch()
                && Limits.getFutureCalls() < Limits.getLimitFutureCalls())
                {
                    unzipAttachmentAsync(srcAttId, destObjId, fileNames);
                    return;
                }
        } 
        catch (Exception e)
        {
            unzipAttachment(srcAttId, destObjId, fileNames, false);
            return;
        }

        Attachment src = [SELECT ParentId, Body FROM Attachment WHERE Id=:srcAttId];
        Attachment[] Atts = new List<Attachment>();

        Zippex2 myZippex = new Zippex2(src.Body);

        if (destObjId == null){
            destObjId = src.ParentId;
        }

        if (fileNames == null){
            fileNames = new List<String>(myZippex.getFileNames());
        }
        Blob attBody;
        for (String fileName : fileNames) {
            attBody = myZippex.getFile(fileName);
            if (attBody != null ) {
                Atts.add(new Attachment (ParentId = destObjId,
                                      Name = fileName, 
                                      Body = myZippex.getFile(fileName)));
            }
            attBody = null;
            //if (Limits.getHeapSize() >= .2 * Limits.getLimitHeapSize()){
            //    insert Atts;
            //    Atts.clear();
            //}
        }
        insert Atts;
    }
    @future
    private static void unzipAttachmentAsync(Id srcAttId, Id destObjId, String[] fileNames){
        unzipAttachment(srcAttId, destObjId, fileNames, false);        
    }

    // Extracts the specified file contents from the current Zip archive.  If the file does not exist, returns null.
    public Blob getFile(String fileName)
    {
        if (!containsFile(fileName)) 
        {
            return null;
        }

        compression.ZipEntry tempFileObject;
        if (zipWriter!=null) 
        {
            tempFileObject = zipWriter.getEntry(fileName);
        }
        else
        {
            tempFileObject = zipReader.getEntry(fileName);
        }
        if (tempFileObject==null) 
        {
            //Should never happen thanks to the check up above, but JUST IN CASE....
            return null;
        }
        return tempFileObject.getContent();
    }

    //  Returns file metadata (lastModDateTime, crc32, fileSize, fileName, and fileComment).
    public Map<String,String> getFileInfo(String fileName)
    {
        if (!containsFile(fileName)) 
        {
            return null;
        }

        compression.ZipEntry entry;
        if (zipWriter!=null) 
        {
            entry = zipReader.getEntry(fileName);
        }
        else
        {
            entry = zipReader.getEntry(fileName);
        }
        if (entry==null) 
        {
            //Should never happen thanks to the check up above, but JUST IN CASE....
            return null;
        }

        Map<String,String> fileInfo = new Map<String,String>();
        fileInfo.put('lastModDateTime', String.valueOf(entry.getLastModifiedTime()));
        fileInfo.put('crc32'          , String.valueOf(entry.getCrc()));
        fileInfo.put('fileSize'       , String.valueOf(entry.getUncompressedSize()));
        fileInfo.put('fileName'       , entry.getName());
        fileInfo.put('fileComment'    , entry.getComment());

        return fileInfo;
    }

    // Returns a Blob that contains the entire Zip archive.
    public Blob getZipArchive()
    {
        if (zipWriter==null) {
            switchToZipWriter();
        }
        return zipWriter.getArchive();
    }

    // Removes a file from the current Zip archive.
    public void removeFile(String fileName){
        switchToZipWriter();

        if (zipWriter.getEntry(fileName)==null)
        {
            return;
        }

        zipWriter.removeEntry(fileName);
    }

    //  Adds a new file to the current Zip archive.
    public void addFile(String fileName, Blob fileData, String crc32)
    {
        addFile(fileName, fileData); //Ignore CRC32, we'll be calculating it ourselves
    }

    public void addFile(String fileName, Blob fileData)
    {
        switchToZipWriter();

        if (containsFile(fileName)){
            removeFile(fileName);
        }

        zipWriter.addEntry(fileName, fileData);
    }

    // Renames a file in the current Zip archive.
    public void renameFile(String oldName, String newName)
    {
        switchToZipWriter();

        if (!containsFile(oldName)) {
            return;
        }

        compression.ZipEntry oldEntry = zipWriter.getEntry(oldName);

        String comment = oldEntry.getComment();
        DateTime lastMod = oldEntry.getLastModifiedTime();
        compression.Method compressionMethod = oldEntry.getMethod();
        Blob data = oldEntry.getContent();

        zipWriter.removeEntry(oldEntry.getName());

        zipWriter.addEntry(newName, 
                           comment,
                           lastMod,
                           compressionMethod,
                           data);
    }

    // Removes the specified prefix from all file names in the current Zip archive only if it occurs at the beginning of the file name.
    public void removePrefix(String prefix)
    {
        switchToZipWriter();
     
        for (String fileName : getFileNames()){
            if (fileName.startsWith(prefix))
            {
                renameFile(fileName, fileName.removeStart(prefix));
            }
        }
    }
}