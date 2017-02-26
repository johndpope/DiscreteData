# DiscreteData
Replacement of Swift Foundation.Data, optimized for chunked data and data require amount of modifications.

# Features 
- No copy even on write
- Reducing physical memory required for payloads contains repeated contents.
- Support vector read/write on file descriptors and socket
- Writtern in pure Swift

# ToDo
- This project is still in development. Please feel free to contribute and sumit PM.
- Implement minium window size (same of the page size) to reduce RAM to cache operations. 
- Flags argument for more optimization flags
- Super Long Term Goal: Replace the Standard Library Data (?)
