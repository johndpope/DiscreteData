# DiscreteData
[![codebeat badge](https://codebeat.co/badges/2cfe4b74-6a72-4d15-ae43-7b85db3b0b2e)](https://codebeat.co/projects/github-com-michael-yuji-discretedata)
![](https://img.shields.io/badge/OS-Darwin|Linux-lightgrey.svg)
[![License](https://img.shields.io/badge/License-BSD%202--Clause-orange.svg)](https://opensource.org/licenses/BSD-2-Clause)

Replacement of Swift Foundation.Data, optimized for chunked data and data require amount of modifications.

# Features 
- Zero copy
- Reducing physical memory required for payloads contains repeated contents.
- Support vector read/write on file descriptors and socket
- Writtern in pure Swift

# ToDo
- This project is still in development. Please feel free to contribute and sumit PM.
- Implement minium window size (same of the page size) to reduce RAM to cache operations. 
- Flags argument for more optimization flags
- Super Long Term Goal: Replace the Standard Library Data (?)
