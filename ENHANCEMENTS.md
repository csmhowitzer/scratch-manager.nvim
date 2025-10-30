# Scratch Manager Enhancements

## Planned Enhancements

### 🎯 **High Priority**

#### **Keymap Defaults Standardization**
- **Status**: Planned
- **Description**: Update default keymaps to match other plugin conventions
- **Current keymaps**: 
  - `==` (toggle)
  - `=c` (toggle with language)
  - `=s` (select)
  - `=d` (delete)
- **Goal**: Research and align with common plugin keymap patterns
- **Examples to research**:
  - Telescope keymaps
  - Oil.nvim keymaps  
  - Other file/buffer management plugins
- **Considerations**: Maintain backward compatibility, provide migration guide

### 🔧 **Medium Priority**

#### **UI Enhancements**
- **Configurable column widths** - Allow users to customize display widths
- **Dynamic window sizing** - Adjust window size based on content
- **Pagination improvements** - Better handling of large scratch buffer lists

#### **Functionality Enhancements**
- **Scoped selection** - Limit selection to specific workspace/root
- **Search/filter** - Quick search within scratch buffer list

#### **Interactive File Management** 🎯
**Priority**: Medium-High
**Complexity**: 7-8/10 (broken into 4 phases)
**Status**: Tracked in dedicated document
**Description**: Transform the selection grid into an editable buffer for direct file operations.

**📋 Dedicated Tracking**: See `INTERACTIVE_FILE_MANAGEMENT.md` for detailed phase breakdown, deliverables, and progress tracking.

**Core Concept**: Make the selection grid behave like a native Neovim buffer where users can edit filenames and delete lines to perform actual file operations.

**Development Phases**:
1. **Foundation** (4/10) - Editable buffer with change detection
2. **Rename Operations** (5/10) - Filename renaming functionality
3. **Delete Operations** (3/10) - File deletion functionality
4. **Polish & Edge Cases** (2/10) - Error handling and UX improvements

**Key Benefits**:
- **Intuitive**: Uses standard Vim editing patterns users already know
- **Efficient**: Batch operations with single confirmation
- **Flexible**: Supports complex rename/delete combinations
- **Consistent**: Feels like native Neovim file management (similar to oil.nvim)

**Quality Assurance**: Each phase includes comprehensive 6AC compliance checks and breaking change validation to ensure existing functionality remains intact.

### 📋 **Low Priority**

#### **Developer Experience**
- **Enhanced error handling** - Better user feedback for edge cases
- **Performance optimizations** - Optimize for large numbers of scratch buffers
- **Documentation improvements** - More examples and use cases

#### **Smart Buffer Persistence** 🧠
**Priority**: Medium
**Complexity**: 4/10
**Description**: Enhance scratch buffer saving logic to avoid persisting empty or unchanged buffers.

**Current Behavior**: All scratch buffers are saved when closed, even if they contain only whitespace or no changes from the initial state.

**Proposed Behavior**:
- Skip saving buffers that contain only whitespace (spaces, tabs, newlines)
- Skip saving buffers that haven't been modified from their initial empty state
- Skip saving buffers that were opened and immediately closed without content
- Provide configuration option to control this behavior

**Implementation Considerations**:
- Check buffer content before save using `vim.api.nvim_buf_get_lines()`
- Track initial buffer state to detect actual changes
- Add configuration option: `smart_persistence = true` (default)
- Maintain backward compatibility for users who want all buffers saved

**Benefits**:
- Cleaner scratch buffer list without empty entries
- Better user experience when browsing existing buffers
- Reduced storage of meaningless buffer files
- More intentional scratch buffer management

**Note**: This enhancement is separate from the Interactive File Management feature above.

## Completed Enhancements ✅

### **v1.0 Release Features**
- ✅ **Native footer implementation** - Integrated footer with action hints and file count
- ✅ **Icon persistence fix** - Colored icons maintain color during navigation
- ✅ **Professional UI** - Three-window architecture with proper highlighting
- ✅ **Comprehensive test suite** - 41 tests across all modules
- ✅ **Health check integration** - Full diagnostic capabilities
- ✅ **Help documentation** - Professional vim help docs
- ✅ **6AC compliance** - All six Augment Code standards met

### **v1.1+ Code Quality Enhancements (Session 22)**
- ✅ **Performance Optimization** - Git branch caching for 2x+ speed improvement
- ✅ **Magic Numbers Elimination** - Named constants for all layout calculations
- ✅ **Icon & Truncation Logic Simplified** - Centralized utilities with proper fallbacks
- ✅ **Layout Function Decomposition** - Split monolithic function into focused, testable components
- ✅ **Enhanced Test Suite** - Expanded from 41 to 92 comprehensive tests (100% passing)
- ✅ **Pattern Compliance** - Proper M._function_name exposure throughout codebase
- ✅ **Architecture Refactoring** - Clean separation of concerns and maintainable code structure

### **v1.1 Critical Bug Fixes (Session 21)**
- ✅ **Missing Item Display Bug** - Fixed session21 dev.lua visibility issue
- ✅ **Window Positioning Fix** - Corrected content window positioning (`row + 2` → `row + 3`)
- ✅ **Selection Highlighting Fix** - Fixed 0-based buffer line conversion for proper highlighting
- ✅ **Cursor Position Alignment** - Corrected cursor positioning to match selection highlight
- ✅ **Max Items Configuration** - Fixed off-by-one issue in max_items display logic
- ✅ **Navigation Wrap-Around** - Corrected wrap-around logic for proper list navigation

## Implementation Priority Order

### **Recommended Development Sequence**:
1. **Interactive File Management** (7-8/10 complexity) - High user impact, transforms UX
2. **Smart Buffer Persistence** (4/10 complexity) - Quality of life improvement
3. **UI Enhancements** (6/10 complexity) - Polish and configurability
4. **Keymap Standardization** (3/10 complexity) - Community alignment

### **Development Notes**:
- **Interactive File Management** represents the biggest UX leap - making scratch-manager feel like native Neovim file management
- **Architecture Advantage**: The existing encoded filename system perfectly supports the interactive enhancement
- **User Experience**: Leverages existing Vim knowledge instead of requiring new keymap learning
- **Community Impact**: Positions scratch-manager as a more sophisticated file management tool

---

## Notes

- All enhancements should maintain the established quality standards
- New features require comprehensive tests
- UI changes should be configurable when possible
- Breaking changes require deprecation warnings and migration guides
