//
//  SLExpandableTableView.m
//  iGithub
//
//  Created by me on 11.04.11.
//  Copyright 2011 Home. All rights reserved.
//

#import "SLExpandableTableView.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

static BOOL protocol_containsSelector(Protocol *protocol, SEL selector)
{
    return protocol_getMethodDescription(protocol, selector, YES, YES).name != NULL || protocol_getMethodDescription(protocol, selector, NO, YES).name != NULL;
}



@interface SLExpandableTableView ()

@property (nonatomic, retain) NSMutableDictionary *expandableSectionsDictionary;
@property (nonatomic, retain) NSMutableDictionary *showingSectionsDictionary;
@property (nonatomic, retain) NSMutableDictionary *downloadingSectionsDictionary;
@property (nonatomic, retain) NSMutableDictionary *animatingSectionsDictionary;

@property (nonatomic, retain) UIView *storedTableHeaderView;
@property (nonatomic, retain) UIView *storedTableFooterView;

@property (atomic, assign) BOOL animating;
@property (nonatomic, assign) NSInteger chainSection; // if -1, means no chain action

- (void)downloadDataInSection:(NSInteger)section;

- (void)_resetExpansionStates;
- (BOOL)isCellFullyVisible:(NSIndexPath*)path;

@end



@implementation SLExpandableTableView

#pragma mark - setters and getters

- (id<UITableViewDelegate>)delegate {
    return [super delegate];
}

- (void)setDelegate:(id<SLExpandableTableViewDelegate>)delegate {
    _myDelegate = delegate;
    if (delegate) {
        //Set delegate to self only if original delegate is not nil
        [super setDelegate:self];
    } else{
        [super setDelegate:nil];
    }
}

- (id<UITableViewDataSource>)dataSource {
    return [super dataSource];
}

- (void)setDataSource:(id<SLExpandableTableViewDatasource>)dataSource {
    _myDataSource = dataSource;
    [super setDataSource:self];
}

- (BOOL)isCellFullyVisible:(NSIndexPath*)path {
	CGRect rect = [self rectForRowAtIndexPath:path];
	rect = [self convertRect:rect toView:self.superview];
	BOOL completelyVisible = CGRectContainsRect(self.frame, rect);
	return completelyVisible;
}

- (void)setTableFooterView:(UIView *)tableFooterView {
    if (tableFooterView != _storedTableFooterView) {
        [super setTableFooterView:nil];
        _storedTableFooterView = tableFooterView;
        [self reloadData];
    }
}

- (void)setTableHeaderView:(UIView *)tableHeaderView {
    if (tableHeaderView != _storedTableHeaderView) {
        [super setTableHeaderView:nil];
        _storedTableHeaderView = tableHeaderView;
        [self reloadData];
    }
}

- (void)setOnlyDisplayHeaderAndFooterViewIfTableViewIsNotEmpty:(BOOL)onlyDisplayHeaderAndFooterViewIfTableViewIsNotEmpty {
    if (_onlyDisplayHeaderAndFooterViewIfTableViewIsNotEmpty != onlyDisplayHeaderAndFooterViewIfTableViewIsNotEmpty) {
        _onlyDisplayHeaderAndFooterViewIfTableViewIsNotEmpty = onlyDisplayHeaderAndFooterViewIfTableViewIsNotEmpty;
        [self reloadData];
    }
}

#pragma mark - NSObject

- (BOOL)respondsToSelector:(SEL)aSelector
{
    if (protocol_containsSelector(@protocol(UITableViewDataSource), aSelector)) {
        return [super respondsToSelector:aSelector] || [_myDataSource respondsToSelector:aSelector];
    } else if (protocol_containsSelector(@protocol(UITableViewDelegate), aSelector)) {
        return [super respondsToSelector:aSelector] || [_myDelegate respondsToSelector:aSelector];
    }

    return [super respondsToSelector:aSelector];
}

- (id)forwardingTargetForSelector:(SEL)aSelector
{
    if (protocol_containsSelector(@protocol(UITableViewDataSource), aSelector)) {
        return _myDataSource;
    } else if (protocol_containsSelector(@protocol(UITableViewDelegate), aSelector)) {
        return _myDelegate;
    }

    return [super forwardingTargetForSelector:aSelector];
}

#pragma mark - Initialization

- (id)initWithFrame:(CGRect)frame style:(UITableViewStyle)style {
    if (self = [super initWithFrame:frame style:style]) {
        [self commonInit];
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)decoder {
    if (self = [super initWithCoder:decoder]) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
	self.animating = NO;
	self.lastExpandedSection = -1;
	self.chainSection = -1;
    self.maximumRowCountToStillUseAnimationWhileExpanding = NSIntegerMax;
    self.expandableSectionsDictionary = [NSMutableDictionary dictionary];
    self.showingSectionsDictionary = [NSMutableDictionary dictionary];
    self.downloadingSectionsDictionary = [NSMutableDictionary dictionary];
    self.animatingSectionsDictionary = [NSMutableDictionary dictionary];
    self.reloadAnimation = UITableViewRowAnimationFade;
}

- (void)awakeFromNib
{
    [super awakeFromNib];

    _storedTableHeaderView = self.tableHeaderView;
    _storedTableFooterView = self.tableFooterView;

    self.tableHeaderView = self.tableHeaderView;
    self.tableFooterView = self.tableFooterView;
}

#pragma mark - private methods

- (void)_resetExpansionStates {
    [self.expandableSectionsDictionary removeAllObjects];
    [self.showingSectionsDictionary removeAllObjects];
    [self.downloadingSectionsDictionary removeAllObjects];
}

- (void)downloadDataInSection:(NSInteger)section {
	if(![@YES isEqual:self.downloadingSectionsDictionary[@(section)]]) {
		// if single expand, we need cancel previous download section
		if(self.singleExpand) {
			for(NSNumber* sec in [self.downloadingSectionsDictionary allKeys]) {
				if([@YES isEqual:self.downloadingSectionsDictionary[sec]]) {
					[self cancelDownloadInSection:[sec integerValue]];
					break;
				}
			}
		}
		
		// set flag to true
		(self.downloadingSectionsDictionary)[@(section)] = @YES;
		
		// call delegate
		[self.myDelegate tableView:self downloadDataForExpandableSection:section];
		
		// reload row
		[self reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:0 inSection:section]]
					withRowAnimation:UITableViewRowAnimationNone];
	}
}

#pragma mark - instance methods

- (BOOL)canExpandSection:(NSUInteger)section {
    return [self.expandableSectionsDictionary[@(section)] boolValue];
}

- (void)reloadDataAndResetExpansionStates:(BOOL)resetFlag {
    if (resetFlag) {
        [self _resetExpansionStates];
    }

    if (self.onlyDisplayHeaderAndFooterViewIfTableViewIsNotEmpty) {
        if ([self numberOfSections] > 0) {
            if ([super tableFooterView] != self.storedTableFooterView) {
                [super setTableFooterView:self.storedTableFooterView];
            }
            if ([super tableHeaderView] != self.storedTableHeaderView) {
                [super setTableHeaderView:self.storedTableHeaderView];
            }
        }
    } else {
        if ([super tableFooterView] != self.storedTableFooterView) {
            [super setTableFooterView:self.storedTableFooterView];
        }
        if ([super tableHeaderView] != self.storedTableHeaderView) {
            [super setTableHeaderView:self.storedTableHeaderView];
        }
    }

    [super reloadData];
}

- (void)cancelDownloadInSection:(NSInteger)section {
	if([@YES isEqual:(self.downloadingSectionsDictionary)[@(section)]]) {
		self.downloadingSectionsDictionary[@(section)] = @NO;
		
		// reload
		[self reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:0 inSection:section]]
					withRowAnimation:UITableViewRowAnimationNone];
	}
}

- (void)expandSection:(NSInteger)section animated:(BOOL)animated {
    NSNumber *key = @(section);
    if ([self.showingSectionsDictionary[key] boolValue]) {
        // section is already showing, return
        return;
    }
	
	self.animating = YES;

    [self deselectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:section] animated:NO];

    if ([self.myDataSource tableView:self needsToDownloadDataForExpandableSection:section]) {
        // data is still not ready to be displayed, return
        [self downloadDataInSection:section];
        return;
    }
	
	// save expanded section
	self.lastExpandedSection = section;

    if ([self.myDelegate respondsToSelector:@selector(tableView:willExpandSection:animated:)]) {
        [self.myDelegate tableView:self willExpandSection:section animated:animated];
    }

    self.animatingSectionsDictionary[key] = @YES;

    // remove the download state
    self.downloadingSectionsDictionary[key] = @NO;

    // update the showing state
    self.showingSectionsDictionary[key] = @YES;

	void(^completionBlock)(void) = ^{
		if ([self respondsToSelector:@selector(scrollViewDidScroll:)]) {
			[self scrollViewDidScroll:self];
		}
		
		if ([self.myDelegate respondsToSelector:@selector(tableView:didExpandSection:animated:)]) {
			[self.myDelegate tableView:self didExpandSection:section animated:animated];
		}
		
		[self.animatingSectionsDictionary removeObjectForKey:@(section)];
		
		// ensure sub area is visible
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.001 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			NSIndexPath* subPath = [NSIndexPath indexPathForRow:1 inSection:section];
			if([self cellForRowAtIndexPath:subPath]) {
				if(![self isCellFullyVisible:subPath]) {
					[self scrollToRowAtIndexPath:subPath atScrollPosition:UITableViewScrollPositionNone animated:YES];
				}
			} else {
				@try {
					[self scrollToRowAtIndexPath:subPath atScrollPosition:UITableViewScrollPositionNone animated:YES];
				} @catch(NSException * __unused exception) {
				}
			}
			self.animating = NO;
		});
	};
	
    NSInteger newRowCount = [self.myDataSource tableView:self numberOfRowsInSection:section];
    // now do the animation magic to insert the new cells
    if (animated && newRowCount <= self.maximumRowCountToStillUseAnimationWhileExpanding) {
		[CATransaction begin];
		[CATransaction setCompletionBlock:completionBlock];
		
        [self beginUpdates];

        UITableViewCell<UIExpandingTableViewCell> *cell = (UITableViewCell<UIExpandingTableViewCell> *)[self cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:section]];
        cell.loading = NO;
        [cell setExpansionStyle:UIExpansionStyleExpanded animated:YES];

        NSMutableArray *insertArray = [NSMutableArray array];
        for (int i = 1; i < newRowCount; i++) {
            [insertArray addObject:[NSIndexPath indexPathForRow:i inSection:section] ];
        }

        [self insertRowsAtIndexPaths:insertArray withRowAnimation:self.reloadAnimation];

        [self endUpdates];
		
		[CATransaction commit];
    } else {
        [self reloadDataAndResetExpansionStates:NO];
		completionBlock();
    }
}

- (void)collapseSection:(NSInteger)section animated:(BOOL)animated {
    NSNumber *key = @(section);
    if (![self.showingSectionsDictionary[key] boolValue]) {
        // section is not showing, return
        return;
    }
	
	self.animating = YES;

    if ([self.myDelegate respondsToSelector:@selector(tableView:willCollapseSection:animated:)]) {
        [self.myDelegate tableView:self willCollapseSection:section animated:animated];
    }

    [self deselectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:section] animated:NO];

    self.animatingSectionsDictionary[key] = @YES;

    // update the showing state
    self.showingSectionsDictionary[key] = @NO;

	void(^completionBlock)(void) = ^{
		if ([self respondsToSelector:@selector(scrollViewDidScroll:)]) {
			[self scrollViewDidScroll:self];
		}
		
		if ([self.myDelegate respondsToSelector:@selector(tableView:didCollapseSection:animated:)]) {
			[self.myDelegate tableView:self didCollapseSection:section animated:animated];
		}
		
		[self.animatingSectionsDictionary removeObjectForKey:@(section)];
		
		// perform chain action or end
		if(self.chainSection > -1) {
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.001 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
				NSNumber* key = @(self.chainSection);
				self.chainSection = -1;
				if([self.showingSectionsDictionary[key] boolValue]) {
					[self collapseSection:[key integerValue] animated:YES];
				} else {
					[self expandSection:[key integerValue] animated:YES];
				}
			});
		} else {
			self.animating = NO;
		}
	};
	
    NSInteger newRowCount = [self.myDataSource tableView:self numberOfRowsInSection:section];
    // now do the animation magic to delete the new cells
    if (animated && newRowCount <= self.maximumRowCountToStillUseAnimationWhileExpanding) {
		[CATransaction begin];
		[CATransaction setCompletionBlock:completionBlock];
		
		[self beginUpdates];
		
		UITableViewCell<UIExpandingTableViewCell> *cell = (UITableViewCell<UIExpandingTableViewCell> *)[self cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:section]];
		cell.loading = NO;
		[cell setExpansionStyle:UIExpansionStyleCollapsed animated:YES];
		
		NSMutableArray *deleteArray = [NSMutableArray array];
		for (int i = 1; i < newRowCount; i++) {
			[deleteArray addObject:[NSIndexPath indexPathForRow:i inSection:section] ];
		}
		
		[self deleteRowsAtIndexPaths:deleteArray withRowAnimation:self.reloadAnimation];
		
		[self endUpdates];
		
		[CATransaction commit];
    } else {
        [self reloadDataAndResetExpansionStates:NO];
		completionBlock();
    }
}

- (BOOL)isSectionExpanded:(NSInteger)section {
    NSNumber *key = @(section);
    return [self.showingSectionsDictionary[key] boolValue];
}

#pragma mark - super implementation

- (void)reloadData {
    [self reloadDataAndResetExpansionStates:YES];
}

- (void)deleteSections:(NSIndexSet *)sections withRowAnimation:(UITableViewRowAnimation)animation {
    NSUInteger indexCount = self.numberOfSections;
    
    NSUInteger currentIndex = sections.firstIndex;
    NSInteger currentShift = 1;
    while (currentIndex != NSNotFound) {
        NSUInteger nextIndex = [sections indexGreaterThanIndex:currentIndex];
        
        if (nextIndex == NSNotFound) {
            nextIndex = indexCount;
        }

        for (NSInteger i = currentIndex + 1; i < nextIndex; i++) {
            NSUInteger newIndex = i - currentShift;
            self.expandableSectionsDictionary[@(newIndex)] = @([self.expandableSectionsDictionary[@(i)] boolValue]);
            self.showingSectionsDictionary[@(newIndex)] = @([self.showingSectionsDictionary[@(i)] boolValue]);
            self.downloadingSectionsDictionary[@(newIndex)] = @([self.downloadingSectionsDictionary[@(i)] boolValue]);
            self.animatingSectionsDictionary[@(newIndex)] = @([self.animatingSectionsDictionary[@(i)] boolValue]);
        }

        currentShift++;
        currentIndex = [sections indexLessThanIndex:currentIndex];
    }

    [super deleteSections:sections withRowAnimation:animation];
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    NSNumber *key = @(indexPath.section);
    NSNumber *value = self.animatingSectionsDictionary[key];
    if ([value boolValue]) {
        if ([self.myDelegate respondsToSelector:@selector(tableView:willDisplayCell:forRowAtIndexPathWhileAnimatingSection:)]) {
            [self.myDelegate tableView:self willDisplayCell:cell forRowAtIndexPathWhileAnimatingSection:indexPath];
        }
    } else {
        if ([self.myDelegate respondsToSelector:@selector(tableView:willDisplayCell:forRowAtIndexPath:)]) {
            [self.myDelegate tableView:tableView willDisplayCell:cell forRowAtIndexPath:indexPath];
        }
    }
}

// Called after the user changes the selection.
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSNumber *key = @(indexPath.section);
    if ([self.expandableSectionsDictionary[key] boolValue]) {
        // section is expandable
        if (indexPath.row == 0) {
            // expand cell got clicked
            if ([self.myDataSource tableView:self needsToDownloadDataForExpandableSection:indexPath.section]) {
				// collapse previous section if single expand is set
				if(self.singleExpand && self.lastExpandedSection >= 0) {
					if(self.lastExpandedSection != indexPath.section) {
						[self collapseSection:self.lastExpandedSection animated:YES];
					}
					self.lastExpandedSection = -1;
				}
				
                // we need to download some data first
                [self downloadDataInSection:indexPath.section];
            } else if(!self.animating) {
				// if only allow one section expanded, we need collapse last expanded section
				// also we need cancel downloading if has one section is in downloading state
				self.chainSection = -1;
				if(self.singleExpand) {
					if(self.lastExpandedSection >= 0) {
						if(self.lastExpandedSection != indexPath.section) {
							self.chainSection = indexPath.section;
							[self collapseSection:self.lastExpandedSection animated:YES];
						}
						self.lastExpandedSection = -1;
					} else {
						for(NSNumber* sec in [self.downloadingSectionsDictionary allKeys]) {
							if([@YES isEqual:self.downloadingSectionsDictionary[sec]]) {
								if([sec integerValue] != indexPath.section) {
									[self cancelDownloadInSection:[sec integerValue]];
								}
								break;
							}
						}
					}
				}
				
				// if no chain action, perform collapse/expand now
				if(self.chainSection == -1) {
					if ([self.showingSectionsDictionary[key] boolValue]) {
						[self collapseSection:indexPath.section animated:YES];
					} else {
						[self expandSection:indexPath.section animated:YES];
					}
				}
            }
        } else {
            if ([self.myDelegate respondsToSelector:@selector(tableView:didSelectRowAtIndexPath:)]) {
                [self.myDelegate tableView:tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:indexPath.row inSection:indexPath.section] ];
            }
        }
    } else {
        if ([self.myDelegate respondsToSelector:@selector(tableView:didSelectRowAtIndexPath:)]) {
            [self.myDelegate tableView:tableView didSelectRowAtIndexPath:indexPath];
        }
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSNumber *key = @(section);
    if ([self.myDataSource tableView:self canExpandSection:section]) {
        if ([self.myDataSource tableView:tableView numberOfRowsInSection:section] == 0) {
            return 0;
        }
        self.expandableSectionsDictionary[key] = @YES;

        if ([self.showingSectionsDictionary[key] boolValue]) {
            return [self.myDataSource tableView:tableView numberOfRowsInSection:section];
        } else {
            return 1;
        }
    } else {
        self.expandableSectionsDictionary[key] = @NO;
        // expanding is not supported
        return [self.myDataSource tableView:tableView numberOfRowsInSection:section];
    }
    return 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSNumber *key = @(indexPath.section);
    if (![self.expandableSectionsDictionary[key] boolValue]) {
        return [self.myDataSource tableView:tableView cellForRowAtIndexPath:indexPath];
    } else {
        // cell is expandable
        if (indexPath.row == 0) {
            UITableViewCell<UIExpandingTableViewCell> *cell = [self.myDataSource tableView:self expandingCellForSection:indexPath.section];
            if ([self.downloadingSectionsDictionary[key] boolValue]) {
                [cell setLoading:YES];
            } else {
                [cell setLoading:NO];
                if ([self.showingSectionsDictionary[key] boolValue]) {
                    [cell setExpansionStyle:UIExpansionStyleExpanded animated:NO];
                } else {
                    [cell setExpansionStyle:UIExpansionStyleCollapsed animated:NO];
                }
            }
            return cell;
        } else {
            return [self.myDataSource tableView:tableView cellForRowAtIndexPath:indexPath];
        }
    }
    return nil;
}

@end
