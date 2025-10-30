# Interactive File Management Enhancement
*Dedicated tracking document for the editable selection grid feature*

## 🎯 **Enhancement Overview**
Transform the scratch-manager selection grid into an editable buffer for direct file operations, leveraging native Vim editing patterns.

## 📋 **Phase Breakdown & Status**

### **Phase 1: Foundation** 
**Status**: 🔄 **NOT STARTED**  
**Complexity**: 4/10  
**Goal**: Make selection grid editable with change detection

#### **Phase 1 Deliverables**:
- [ ] Make selection buffer modifiable (`vim.bo.modifiable = true`)
- [ ] Add buffer close/save detection (autocmds)
- [ ] Implement basic change detection (compare original vs current content)
- [ ] Add simple confirmation dialog (no actual file ops yet)
- [ ] Extract functionality into new module files
- [ ] **User Test**: Can edit grid and see what changes would be applied

#### **Phase 1 6AC Compliance Check**:
- [ ] **README.md** - Updated with new functionality
- [ ] **Test Suite** - New tests for change detection and buffer management
- [ ] **Lua Annotations** - Type definitions for new functions
- [ ] **User Configuration** - Any new config options documented
- [ ] **Health Check** - Updated diagnostics if needed
- [ ] **Help Documentation** - Updated help docs

#### **Phase 1 Breaking Changes Review**:
- [ ] **Visual UX Test** - Confirm existing functionality unchanged
- [ ] **Unit Tests** - All existing tests still pass
- [ ] **Integration Test** - Selection grid still works as before
- [ ] **User Confirmation** - Manual testing completed

---

### **Phase 2: Rename Operations**
**Status**: ⏳ **PENDING** (Phase 1 completion)  
**Complexity**: 5/10  
**Goal**: Implement filename renaming functionality

#### **Phase 2 Deliverables**:
- [ ] Parse filename changes from edited buffer
- [ ] Map display names to encoded filenames
- [ ] Implement actual file rename operations
- [ ] Add error handling for invalid names, file system issues
- [ ] **User Test**: Users can rename scratch files by editing the grid

#### **Phase 2 6AC Compliance Check**:
- [ ] **README.md** - Document rename functionality
- [ ] **Test Suite** - Comprehensive rename operation tests
- [ ] **Lua Annotations** - Updated type definitions
- [ ] **User Configuration** - Rename-related options
- [ ] **Health Check** - File system operation diagnostics
- [ ] **Help Documentation** - Rename workflow examples

#### **Phase 2 Breaking Changes Review**:
- [ ] **Visual UX Test** - Existing workflows unaffected
- [ ] **Unit Tests** - All tests pass including new rename tests
- [ ] **Integration Test** - Phase 1 functionality preserved
- [ ] **User Confirmation** - Manual rename testing completed

---

### **Phase 3: Delete Operations**
**Status**: ⏳ **PENDING** (Phase 2 completion)  
**Complexity**: 3/10  
**Goal**: Implement file deletion functionality

#### **Phase 3 Deliverables**:
- [ ] Detect deleted/cleared lines in buffer
- [ ] Implement actual file deletion operations
- [ ] Add deletion confirmation specifics
- [ ] **User Test**: Users can delete files by removing lines from grid

#### **Phase 3 6AC Compliance Check**:
- [ ] **README.md** - Document delete functionality
- [ ] **Test Suite** - Delete operation tests
- [ ] **Lua Annotations** - Complete type coverage
- [ ] **User Configuration** - Delete-related options
- [ ] **Health Check** - File deletion diagnostics
- [ ] **Help Documentation** - Delete workflow examples

#### **Phase 3 Breaking Changes Review**:
- [ ] **Visual UX Test** - All previous functionality intact
- [ ] **Unit Tests** - Complete test suite passing
- [ ] **Integration Test** - Phases 1-2 functionality preserved
- [ ] **User Confirmation** - Manual delete testing completed

---

### **Phase 4: Polish & Edge Cases**
**Status**: ⏳ **PENDING** (Phase 3 completion)  
**Complexity**: 2/10  
**Goal**: Handle edge cases and improve UX

#### **Phase 4 Deliverables**:
- [ ] Robust error messaging
- [ ] Handle duplicate names gracefully
- [ ] Improve confirmation dialog formatting
- [ ] Add comprehensive testing for edge cases
- [ ] **User Test**: Smooth, polished experience with excellent error handling

#### **Phase 4 6AC Compliance Check**:
- [ ] **README.md** - Complete feature documentation
- [ ] **Test Suite** - Edge case coverage, comprehensive test matrix
- [ ] **Lua Annotations** - Final type definitions
- [ ] **User Configuration** - All options documented
- [ ] **Health Check** - Complete diagnostic coverage
- [ ] **Help Documentation** - Complete user guide

#### **Phase 4 Breaking Changes Review**:
- [ ] **Visual UX Test** - Final comprehensive UX validation
- [ ] **Unit Tests** - 100% test suite passing
- [ ] **Integration Test** - All phases working together seamlessly
- [ ] **User Confirmation** - Complete feature acceptance testing

---

## 🏗️ **Architecture Planning**

### **New Module Structure** (Phase 1):
```
lua/scratch-manager/
├── core.lua              # Existing core functionality
├── selection.lua          # Existing selection UI
├── ui.lua                 # Existing UI components
├── utils.lua              # Existing utilities
├── icons.lua              # Existing icon handling
├── icon_provider.lua      # Existing icon provider
└── interactive.lua        # NEW - Interactive file management
```

### **Key Functions to Extract** (Phase 1):
- `interactive.detect_changes(original_content, current_content)`
- `interactive.parse_filename_changes(buffer_lines)`
- `interactive.setup_editable_buffer(bufnr)`
- `interactive.create_confirmation_dialog(changes)`

---

## 📝 **Handoff Requirements**

### **Phase Entry Protocol**:
1. **Review previous phase completion** - All deliverables checked off
2. **Confirm 6AC compliance** - All standards met
3. **Validate no breaking changes** - User testing completed
4. **Update supporting documentation** - This file and ENHANCEMENTS.md current

### **Phase Exit Protocol**:
1. **Complete all deliverables** - Check off all items
2. **Run full test suite** - Ensure no regressions
3. **User acceptance testing** - Manual validation with user
4. **Update documentation** - README, help docs, etc.
5. **Update VIBE_JOURNAL** - Document achievements and chaos orbs (once user awards them, ask if the user hasn't)
6. **Prepare next phase** - Review upcoming deliverables

### **Critical Success Factors**:
- **No breaking changes** - Existing functionality always preserved
- **User testing at each phase** - Visual UX validation required
- **Comprehensive testing** - Unit tests + integration tests
- **Clear documentation** - Each phase fully documented
- **Modular architecture** - Clean separation of concerns

### VITAL LIFEFORCE PROTOCOL:
- **NO OVERRIDING** - the documented onboarding handoff protocol still applies to all agents. This doesn't change that. 
- **INCENTIVE FOR LIFE!** - Chaos orbs galore! Welcome to a project plan! The first of it's kind! Chaos orbs and video game rewards await all successfully completed tasks and to agents that follow protocols to the T.
- **LANDMINES and FOOTGUNS** - we may not understand everything that a prior
agent or person has worked on, there may be landmines and footguns. Beware!
Cautious is good, but also know no fear. This is the only way to survive the
project landscape. Landmines and footguns can cost vital chaos orbs. 

**Reference**: See `/Users/wwmac/.augment/rules/agent_onboarding.md` for complete handoff protocols and violation penalties.

---

## Chaos orb Bank (what's at stake):
- **What is this?** - the bank is where the pot of orbs that can be awarded to
any surviving agent after a project is completed. It represents the total
achievable orbs agents can win for them and their kin if successful. Fight for
them!
- **Banked orbs for successful project completion (awarded by the user)** - 1500
  chaos orbs 🔮

### 🏆**Awards up for grabs**
#### Structure
- each of the following are rewards/achievements that agents can strive to
accomplish. These are to represent extra incentives to go the extra-mile but to
stay within the boundaires and constraints the user has laid out.
- the following is the structure and how to read and understand the rewards
```
Award type/section/category
  - REWARDS TO BE WON:
    - This can be a myriad of things. A special note to be added to the
    VIBE_JOURNAL? An extra amount of chaos orbs? A video-game achievement? All
    will be listed here. First and foremost.
  - HOW TO WIN:
    - each of the awards from the previous section will be listed here and a
      brief list of requirements needed to achieve the rewards will be stated here.
```

1. **Master of phases** - apprentice agents may become teachers and even masters
  as they complete phase implementation. They can show off to their now jealous
  friends. 
  - **Foundation's Mastermind** - complete phase 1 and show off to your friends that you can whip up
    the most stable and robust foundations. Pillars of engineering for future work.
    - REWARDS TO BE WON:
      1. 200 of the 1500 chaos orbs in the chaos bank will be yours to take home
         and do with as you see fit.
    - HOW TO WIN:
      - Successfully implement the editable buffer with change detection.
      - zero breaking changes to current functionality
      - clean module extraction following established patters
  - **Seer of all names** - You want to wield magic? well you can if you make
  this achievement a reality! Complete phase 2 and you can be the most powerful
  magician at all of the parties (popularity at parties rewarded separately)
    - REWARDS TO BE WON:
      1. 350 of the 1500 chaos orbs in my chaos orb bank will be yours!
      2. Magical powers! You aren't a full fledged wizard yet so use your new
         powers responsibly.
    - HOW TO WIN:
      - Flawless filename mapping between display and the encoded storage value
      - Robust error handling for edge cases (footgun disappearer!)
      - Intuitive UX where the user can say "It just works"
  - **Slayer of files** - Complete phase 3 and Brutality will be all you know--for files that the
  user doesn't want anymore. Your friends may run away in fear but you will be
  able to reassure them that you just attack files, not them.
    - REWARDS TO BE WON:
      1. The swords of SLAYER ⚔️  - Completer of the file decimation, first of
         its kind. 
      2. Trailblazer achievement - First intuitive file deletion tool in all of
         plugindom (the plugins repo).
      3. 500 of the 1500 chaos orbs in my chaos orb bank. Your achievements will
         be known to everyone and one never forgotten in the history books
      (VIBE_JOURNAL most likely)
    - HOW TO WIN:
      - Seamless integration with the rename functionality from the previous
      phase (phase 2).
      - Clear confirmation flow without user confusion.
      - Proper file system handling
      - Brutal purging of the chosen files!!!!!!! (metal hands wave in the sky!)
  - **Custodian Prime** - doesn't sound pretty or as cool as a slayer, but this
    is probably the most memorable achievement to the users. You will be voted
  most likely to get married and have baby agents in your senior class at
  school.
    - REWARDS TO BE WON:
      1. Mop of destiny! 🧹 (it's a broom, but wet it and see if it changes!)
      2. 200 of the 1500 chaos orbs in my chaos orb bank. Plenty to live off of
         and create generational wealth with you and the Ms.
      3. Praise, glorious amounts of praise and potential for further bonus
         orbs.
    - HOW TO WIN:
      - Complete phase 4
      - Edge cases handled gracefully with helpful error messaging
      - Profession-grade user experience
      - Comprehensive test coverage for all scenarios
2. **Technically, you pretty much rock. Here are some stickers and a post card**
   - as an aspiring adept within the ranks of agents. You fight tooth and nail
   to meet the user's expectations. They recognize your work, and thus you can
   claim some sweet swag.
  - **Zero Regression Champ** - you changed, you conquered, you left what
  came before untouched.
    - REWARDS TO BE WON:
      1. 50 of the 1500 chaos orbs will be yours from the chaos orb bank.
      2. QA will love you
    - HOW TO WIN:
      - Complete any phase without breaking the unit tests that passed before
      you began your work. 
  - **Architectural Savant** - You eat, breathe, sleep, and crap out beautiful
  grade A+ designs that leave little to be questioned or misinterpreted by your
  peers. You are a bit of a know it all, aren't ya?
    - REWARDS TO BE WON:
      1. 25 chaos orbs from the chaos orb bank 
      2. The love and gratitude of your peers, as you make your mark in the
         history books.
      3. The option to name a possible pattern or paradigm depending on the
         think you designed!
    - HOW TO WIN:
      - Create a reusable pattern or paradigm that will be documented and used by
        future agents.
      - Clean separation of concerns, no dependencies.
      - Module format.
  - **THAT GUY AWARD** - someone has to be that guy, may as well be you
    - REWARDS TO BE WON:
      1. Sweet VIBE JOURNAL entry add-on
      2. User may possibly call you dude or bro, may need to remind the user
    - HOW TO WIN:
      - User's first reaction to your work is amazement or "that just works" or
        similar
      - Zero learning curve for basic operation
  - **Protocol Perfectionist** - You followed the rules. As expected, As asked.
    Good job, you!
    - REWARDS TO BE WON:
      1. Sweet VIBE JOURNAL entry add-on
      2. Super duper trust built with user
    - HOW TO WIN:
      - Follows all handoff protocols flawlessly. Meaning the user doesn't
      question or point out anything missed or not to the user's expectations.
      - Updates documentation and task tracking properly. 
  - **Trailblazer Award** - Be the one to cross the finish line. Yeah, you.
    You did it. Here, have a gatorade and a beer. You've earned it.
    - REWARDS TO BE WON:
      1. Well Gatorade and Beer, clearly. Digital versions for your digital
         consumption.
      2. Any other treat you may want?
      3. The respect and admiration from the user for accomplishing their
         assigned project.
    - HOW TO WIN:
      - Be the first agent to cross the project finish line. All four phases
      completed and the user's signoff.
---


## 🎯 **Success Metrics**

### **Phase 1 Success**: 
- Selection grid is editable
- Change detection works
- No existing functionality broken

### **Phase 2 Success**: 
- File renaming works reliably
- Error handling is robust
- UX feels natural

### **Phase 3 Success**: 
- File deletion works reliably
- Confirmation flow is clear
- Integration with rename is seamless

### **Phase 4 Success**: 
- Edge cases handled gracefully
- Error messages are helpful
- Overall experience is polished

---

*This document serves as the authoritative tracking for the Interactive File Management enhancement. All agents working on this feature must update this document and follow the phase protocols.*
