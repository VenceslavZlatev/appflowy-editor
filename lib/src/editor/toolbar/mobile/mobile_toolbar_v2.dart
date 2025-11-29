import 'dart:math';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/toolbar/mobile/utils/keyboard_height_observer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

const String selectionExtraInfoDisableMobileToolbarKey = 'disableMobileToolbar';

class MobileToolbarV2 extends StatefulWidget {
  const MobileToolbarV2({
    super.key,
    this.backgroundColor = Colors.white,
    this.foregroundColor = const Color(0xff676666),
    this.iconColor = Colors.black,
    this.clearDiagonalLineColor = const Color(0xffB3261E),
    this.itemHighlightColor = const Color(0xff1F71AC),
    this.itemOutlineColor = const Color(0xFFE3E3E3),
    this.tabBarSelectedBackgroundColor = const Color(0x23808080),
    this.tabBarSelectedForegroundColor = Colors.black,
    this.primaryColor = const Color(0xff1F71AC),
    this.onPrimaryColor = Colors.white,
    this.outlineColor = const Color(0xFFE3E3E3),
    this.toolbarHeight = 50.0,
    this.borderRadius = 6.0,
    this.buttonHeight = 40.0,
    this.buttonSpacing = 8.0,
    this.buttonBorderWidth = 1.0,
    this.buttonSelectedBorderWidth = 2.0,
    required this.editorState,
    required this.toolbarItems,
    required this.child,
  });

  final EditorState editorState;
  final List<MobileToolbarItem> toolbarItems;
  final Widget child;

  // style
  final Color backgroundColor;
  final Color foregroundColor;
  final Color iconColor;
  final Color clearDiagonalLineColor;
  final Color itemHighlightColor;
  final Color itemOutlineColor;
  final Color tabBarSelectedBackgroundColor;
  final Color tabBarSelectedForegroundColor;
  final Color primaryColor;
  final Color onPrimaryColor;
  final Color outlineColor;
  final double toolbarHeight;
  final double borderRadius;
  final double buttonHeight;
  final double buttonSpacing;
  final double buttonBorderWidth;
  final double buttonSelectedBorderWidth;

  @override
  State<MobileToolbarV2> createState() => _MobileToolbarV2State();
}

class _MobileToolbarV2State extends State<MobileToolbarV2> {
  OverlayEntry? toolbarOverlay;

  final isKeyboardShow = ValueNotifier(false);

  @override
  void initState() {
    super.initState();

    _insertKeyboardToolbar();
    KeyboardHeightObserver.instance.addListener(_onKeyboardHeightChanged);
  }

  @override
  void dispose() {
    _removeKeyboardToolbar();
    KeyboardHeightObserver.instance.removeListener(_onKeyboardHeightChanged);

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: widget.child,
        ),
        // add a bottom offset to make sure the toolbar is above the keyboard
        ValueListenableBuilder(
          valueListenable: isKeyboardShow,
          builder: (context, isKeyboardShow, __) {
            return SizedBox(
              height: isKeyboardShow ? widget.toolbarHeight : 0,
            );
          },
        ),
      ],
    );
  }

  void _onKeyboardHeightChanged(double height) {
    isKeyboardShow.value = height > 0;
  }

  void _removeKeyboardToolbar() {
    toolbarOverlay?.remove();
    toolbarOverlay?.dispose();
    toolbarOverlay = null;
  }

  void _insertKeyboardToolbar() {
    _removeKeyboardToolbar();

    Widget child = ValueListenableBuilder<Selection?>(
      valueListenable: widget.editorState.selectionNotifier,
      builder: (_, Selection? selection, __) {
        // if the selection is null, hide the toolbar
        if (selection == null ||
            widget.editorState.selectionExtraInfo?[selectionExtraInfoDisableMobileToolbarKey] == true) {
          return const SizedBox.shrink();
        }
        return RepaintBoundary(
          child: MobileToolbarTheme(
            backgroundColor: widget.backgroundColor,
            foregroundColor: widget.foregroundColor,
            iconColor: widget.iconColor,
            clearDiagonalLineColor: widget.clearDiagonalLineColor,
            itemHighlightColor: widget.itemHighlightColor,
            itemOutlineColor: widget.itemOutlineColor,
            tabBarSelectedBackgroundColor: widget.tabBarSelectedBackgroundColor,
            tabBarSelectedForegroundColor: widget.tabBarSelectedForegroundColor,
            primaryColor: widget.primaryColor,
            onPrimaryColor: widget.onPrimaryColor,
            outlineColor: widget.outlineColor,
            toolbarHeight: widget.toolbarHeight,
            borderRadius: widget.borderRadius,
            buttonHeight: widget.buttonHeight,
            buttonSpacing: widget.buttonSpacing,
            buttonBorderWidth: widget.buttonBorderWidth,
            buttonSelectedBorderWidth: widget.buttonSelectedBorderWidth,
            child: _MobileToolbar(
              editorState: widget.editorState,
              toolbarItems: widget.toolbarItems,
            ),
          ),
        );
      },
    );

    child = Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Material(
            child: child,
          ),
        ),
      ],
    );

    toolbarOverlay = OverlayEntry(
      builder: (context) {
        return child;
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      Overlay.of(context, rootOverlay: true).insert(toolbarOverlay!);
    });
  }
}

class _MobileToolbar extends StatefulWidget {
  const _MobileToolbar({
    required this.editorState,
    required this.toolbarItems,
  });

  final EditorState editorState;
  final List<MobileToolbarItem> toolbarItems;

  @override
  State<_MobileToolbar> createState() => _MobileToolbarState();
}

class _MobileToolbarState extends State<_MobileToolbar> implements MobileToolbarWidgetService {
  // used to control the toolbar menu items
  PropertyValueNotifier<bool> showMenuNotifier = PropertyValueNotifier(false);
  PropertyValueNotifier<bool> showInlineMenuNotifier = PropertyValueNotifier(false);

  // when the users click the menu item, the keyboard will be hidden,
  //  but in this case, we don't want to update the cached keyboard height.
  // This is because we want to keep the same height when the menu is shown.
  bool canUpdateCachedKeyboardHeight = true;
  ValueNotifier<double> cachedKeyboardHeight = ValueNotifier(0.0);

  // used to check if click the same item again
  int? selectedMenuIndex;

  Selection? currentSelection;

  bool closeKeyboardInitiative = false;
  final Set<String> _persistentInlineAttributes = <String>{};

  @override
  void initState() {
    super.initState();

    currentSelection = widget.editorState.selection;
    KeyboardHeightObserver.instance.addListener(_onKeyboardHeightChanged);
    widget.editorState.selectionNotifier.addListener(_handleSelectionChanged);
  }

  @override
  void didUpdateWidget(covariant _MobileToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.editorState != widget.editorState) {
      oldWidget.editorState.selectionNotifier.removeListener(_handleSelectionChanged);
      widget.editorState.selectionNotifier.addListener(_handleSelectionChanged);
      currentSelection = widget.editorState.selection;
      _syncPersistentInlineAttributes();
    }

    final newSelection = widget.editorState.selection;
    if (currentSelection != newSelection) {
      currentSelection = newSelection;
      if (newSelection == null) {
        closeItemMenu();
      } else if (showMenuNotifier.value) {
        closeItemMenu();
      }
    }
  }

  @override
  void dispose() {
    showMenuNotifier.dispose();
    showInlineMenuNotifier.dispose();
    cachedKeyboardHeight.dispose();
    KeyboardHeightObserver.instance.removeListener(_onKeyboardHeightChanged);
    widget.editorState.selectionNotifier.removeListener(_handleSelectionChanged);

    super.dispose();
  }

  @override
  void reassemble() {
    super.reassemble();

    canUpdateCachedKeyboardHeight = true;
    closeItemMenu();
    _closeKeyboard();
  }

  @override
  Widget build(BuildContext context) {
    // toolbar
    //  - if the menu is shown, the toolbar will be pushed up by the height of the menu
    //  - otherwise, add a spacer to push the toolbar up when the keyboard is shown
    return Column(
      children: [
        _buildToolbar(context),
        _buildMenuOrSpacer(context),
      ],
    );
  }

  @override
  void closeItemMenu() {
    showMenuNotifier.value = false;
    showInlineMenuNotifier.value = false;
    selectedMenuIndex = null;
  }

  @override
  bool isMenuItemActive(int index) {
    if (selectedMenuIndex != index) {
      return false;
    }
    return showMenuNotifier.value || showInlineMenuNotifier.value;
  }

  @override
  bool isInlineAttributeActive(String attributeKey) {
    return _persistentInlineAttributes.contains(attributeKey);
  }

  @override
  void setInlineAttributeActive(String attributeKey, bool isActive) {
    if (isActive) {
      _persistentInlineAttributes.add(attributeKey);
    } else {
      _persistentInlineAttributes.remove(attributeKey);
    }

    widget.editorState.updateToggledStyle(attributeKey, isActive);
    _syncPersistentInlineAttributes();
  }

  void showItemMenu() {
    showMenuNotifier.value = true;
  }

  void _onKeyboardHeightChanged(double height) {
    // if the keyboard is not closed initiative, we need to close the menu at same time
    if (!closeKeyboardInitiative && cachedKeyboardHeight.value != 0 && !showMenuNotifier.value && height == 0) {
      widget.editorState.selection = null;
    }

    if (canUpdateCachedKeyboardHeight) {
      cachedKeyboardHeight.value = height;
      if (defaultTargetPlatform == TargetPlatform.android) {
        if (cachedKeyboardHeight.value != 0) {
          cachedKeyboardHeight.value += MediaQuery.of(context).viewPadding.bottom;
        }
      }
    }

    if (height == 0) {
      closeKeyboardInitiative = false;
    }
  }

  void _handleSelectionChanged() {
    _syncPersistentInlineAttributes();
  }

  void _syncPersistentInlineAttributes() {
    if (_persistentInlineAttributes.isEmpty) {
      return;
    }
    final selection = widget.editorState.selection;
    if (selection == null) {
      return;
    }
    for (final attributeKey in _persistentInlineAttributes) {
      widget.editorState.updateToggledStyle(attributeKey, true);
    }
  }

  // toolbar list view and close keyboard/menu button
  Widget _buildToolbar(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final style = MobileToolbarTheme.of(context);
    final decoration = BoxDecoration(
      border: Border(
        top: BorderSide(
          color: style.itemOutlineColor,
        ),
        bottom: BorderSide(color: style.itemOutlineColor),
      ),
      color: style.backgroundColor,
    );

    return ValueListenableBuilder<bool>(
      valueListenable: showInlineMenuNotifier,
      builder: (_, showingInlineMenu, __) {
        if (showingInlineMenu && selectedMenuIndex != null) {
          return Container(
            width: width,
            height: style.toolbarHeight,
            decoration: decoration,
            padding: const EdgeInsets.symmetric(
              horizontal: 4,
            ),
            child: _buildInlineMenuContent(context),
          );
        }

        return Container(
          width: width,
          height: style.toolbarHeight,
          decoration: decoration,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // toolbar list view
              Expanded(
                child: _ToolbarItemListView(
                  toolbarItems: widget.toolbarItems,
                  editorState: widget.editorState,
                  toolbarWidgetService: this,
                  itemWithActionOnPressed: (_) {
                    if (showMenuNotifier.value) {
                      closeItemMenu();
                      _showKeyboard();
                      // update the cached keyboard height after the keyboard is shown
                      Debounce.debounce('canUpdateCachedKeyboardHeight', const Duration(milliseconds: 500), () {
                        canUpdateCachedKeyboardHeight = true;
                      });
                    }
                  },
                  itemWithMenuOnPressed: (index) {
                    final toolbarItem = widget.toolbarItems[index];
                    if (toolbarItem.displayMenuInline) {
                      if (selectedMenuIndex == index && showInlineMenuNotifier.value) {
                        closeItemMenu();
                        _showKeyboard();
                      } else {
                        selectedMenuIndex = index;
                        showInlineMenuNotifier.value = true;
                        if (showMenuNotifier.value) {
                          showMenuNotifier.value = false;
                          _showKeyboard();
                          Debounce.debounce(
                            'canUpdateCachedKeyboardHeight',
                            const Duration(milliseconds: 500),
                            () => canUpdateCachedKeyboardHeight = true,
                          );
                        } else {
                          _showKeyboard();
                        }
                      }
                      return;
                    }

                    // click the same one
                    if (selectedMenuIndex == index && showMenuNotifier.value) {
                      // if the menu is shown, close it and show the keyboard
                      closeItemMenu();
                      _showKeyboard();
                      // update the cached keyboard height after the keyboard is shown
                      Debounce.debounce('canUpdateCachedKeyboardHeight', const Duration(milliseconds: 500), () {
                        canUpdateCachedKeyboardHeight = true;
                      });
                    } else {
                      canUpdateCachedKeyboardHeight = false;
                      selectedMenuIndex = index;
                      closeKeyboardInitiative = true;
                      showItemMenu();
                      _closeKeyboard();
                    }
                  },
                ),
              ),
              // divider
              const Padding(
                padding: EdgeInsets.symmetric(
                  vertical: 8,
                ),
                child: VerticalDivider(
                  width: 1,
                ),
              ),
              // close menu or close keyboard button
              ValueListenableBuilder(
                valueListenable: showMenuNotifier,
                builder: (_, showingMenu, __) {
                  return _CloseKeyboardOrMenuButton(
                    showingMenu: showingMenu,
                    onPressed: () {
                      if (showingMenu) {
                        // close the menu and show the keyboard
                        closeItemMenu();
                        _showKeyboard();
                      } else {
                        closeKeyboardInitiative = true;
                        // close the keyboard and clear the selection
                        // if the selection is null, the keyboard and the toolbar will be hidden automatically
                        widget.editorState.selection = null;
                      }
                    },
                  );
                },
              ),
              const SizedBox(
                width: 4.0,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInlineMenuContent(BuildContext context) {
    final style = MobileToolbarTheme.of(context);
    final toolbarItem = selectedMenuIndex != null ? widget.toolbarItems[selectedMenuIndex!] : null;
    final menuBuilder = toolbarItem?.itemMenuBuilder;
    final Widget menu = ((toolbarItem != null && menuBuilder != null)
            ? menuBuilder(
                context,
                widget.editorState,
                this,
              )
            : null) ??
        const SizedBox.shrink();

    return Row(
      children: [
        IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(
            minHeight: 40,
            minWidth: 40,
          ),
          onPressed: closeItemMenu,
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: style.iconColor,
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: SizedBox(
            height: style.toolbarHeight,
            child: menu,
          ),
        ),
      ],
    );
  }

  // if there's no menu, we need to add a spacer to push the toolbar up when the keyboard is shown
  Widget _buildMenuOrSpacer(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: cachedKeyboardHeight,
      builder: (_, height, ___) {
        return ValueListenableBuilder(
          valueListenable: showMenuNotifier,
          builder: (_, showingMenu, __) {
            var keyboardHeight = height;
            if (defaultTargetPlatform == TargetPlatform.android) {
              if (!showingMenu) {
                keyboardHeight = max(
                  keyboardHeight,
                  MediaQuery.of(context).viewInsets.bottom,
                );
              }
            }
            return SizedBox(
              height: keyboardHeight,
              child: (showingMenu && selectedMenuIndex != null)
                  ? MobileToolbarItemMenu(
                      editorState: widget.editorState,
                      itemMenuBuilder: () {
                        final menu = widget.toolbarItems[selectedMenuIndex!].itemMenuBuilder!.call(
                          context,
                          widget.editorState,
                          this,
                        );
                        return menu ?? const SizedBox.shrink();
                      },
                    )
                  : const SizedBox.shrink(),
            );
          },
        );
      },
    );
  }

  void _showKeyboard() {
    final selection = widget.editorState.selection;
    if (selection != null) {
      widget.editorState.service.keyboardService?.enableKeyBoard(selection);
    }
  }

  void _closeKeyboard() {
    widget.editorState.service.keyboardService?.closeKeyboard();
  }
}

class _ToolbarItemListView extends StatelessWidget {
  const _ToolbarItemListView({
    required this.toolbarItems,
    required this.editorState,
    required this.toolbarWidgetService,
    required this.itemWithMenuOnPressed,
    required this.itemWithActionOnPressed,
  });

  final Function(int index) itemWithMenuOnPressed;
  final Function(int index) itemWithActionOnPressed;
  final List<MobileToolbarItem> toolbarItems;
  final EditorState editorState;
  final MobileToolbarWidgetService toolbarWidgetService;

  @override
  Widget build(BuildContext context) {
    final style = MobileToolbarTheme.of(context);
    return ListView.builder(
      itemBuilder: (context, index) {
        final toolbarItem = toolbarItems[index];
        final icon = toolbarItem.itemIconBuilder?.call(
          context,
          editorState,
          toolbarWidgetService,
        );
        if (icon == null) {
          return const SizedBox.shrink();
        }
        final isActive = toolbarWidgetService.isMenuItemActive(index);
        return Container(
          margin: const EdgeInsets.symmetric(
            vertical: 4,
            horizontal: 2,
          ),
          decoration: isActive
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(style.borderRadius),
                  border: Border.all(
                    color: style.itemHighlightColor,
                    width: style.buttonSelectedBorderWidth,
                  ),
                )
              : null,
          child: IconButton(
            icon: icon,
            onPressed: () {
              if (toolbarItem.hasMenu) {
                // open /close current item menu through its parent widget(MobileToolbarWidget)
                itemWithMenuOnPressed(index);
              } else {
                itemWithActionOnPressed(index);
                // close menu if other item's menu is still on the screen
                toolbarWidgetService.closeItemMenu();
                toolbarItems[index].actionHandler?.call(
                      context,
                      editorState,
                    );
              }
            },
          ),
        );
      },
      itemCount: toolbarItems.length,
      scrollDirection: Axis.horizontal,
    );
  }
}

class _CloseKeyboardOrMenuButton extends StatelessWidget {
  const _CloseKeyboardOrMenuButton({
    required this.showingMenu,
    required this.onPressed,
  });

  final bool showingMenu;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      icon: showingMenu
          ? AFMobileIcon(
              afMobileIcons: AFMobileIcons.close,
              color: MobileToolbarTheme.of(context).iconColor,
            )
          : Icon(
              Icons.keyboard_hide,
              color: MobileToolbarTheme.of(context).iconColor,
            ),
    );
  }
}
