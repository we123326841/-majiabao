//
//  CardViewController.m
//  WordRecognition
//
//  Created by 李超 on 15/12/5.
//  Copyright © 2015年 李超. All rights reserved.
//

#import "CardViewController.h"
#import "DataBase.h"
#import "CardViewBindHelper.h"
#import "Card.h"
#import "CardCollectionViewCell.h"
#import "CardLayout.h"
#import "CardListViewController.h"
#import <iflyMSC/IFlySpeechSynthesizerDelegate.h>
#import <iflyMSC/IFlySpeechError.h>
#import <iflyMSC/IFlySpeechConstant.h>
#import "NetworkManager.h"
#import "YTOperations.h"
#import "UIImage+Resize.h"
#import "YTTagModel.h"

#define IS_CH_SYMBOL(chr) ((int)(chr)>127)
#define MAX_TEXT 6

typedef NS_ENUM(NSUInteger, SaveButtonType) {
    SaveButtonTypeDidSave = 0,
    SaveButtonTypeNotSave,
};

@interface CardViewController ()<UICollectionViewDelegate, UICollectionViewDataSource, CardCollectionViewCellDelegate, IFlySpeechSynthesizerDelegate, UIScrollViewDelegate, UITextFieldDelegate>


@property (nonatomic, strong) CardViewBindHelper *bindHelper;

@property (nonatomic, strong) UIImageView *playButton;
@property (weak, nonatomic) IBOutlet UIButton *saveButton;
@property (weak, nonatomic) IBOutlet UIButton *editButton;
@property (weak, nonatomic) IBOutlet UIButton *refreshButton;
@property (nonatomic, strong) NSMutableArray *indexArray;
@property (nonatomic, assign) NSUInteger indexToDelete;
@property (nonatomic, assign) SaveButtonType buttonType;

@end

@implementation CardViewController

#pragma mark life circle
- (void)viewDidLoad {
    [super viewDidLoad];
    [self setUpSubviews];
    [[VoiceHelper sharedInstance] setSpeechSynthesizerDelegate:self];
}

#pragma mark UICollectionView Delegate and Data Source
- (NSInteger)collectionView:(UICollectionView *)view numberOfItemsInSection:(NSInteger)section;
{
    return self.cardArray.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)indexPath;
{
    CardCollectionViewCell *cell = [cv dequeueReusableCellWithReuseIdentifier:@"cardCell" forIndexPath:indexPath];
    [self.bindHelper bindCardCell:cell withCard:self.cardArray[indexPath.row] index:[self.indexArray objectAtIndex:indexPath.row] num:[NSNumber numberWithInteger:indexPath.row]];
    cell.delegate = self;
    return cell;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation {
    return UIInterfaceOrientationIsLandscape(toInterfaceOrientation);
}

#pragma mark UIScrollViewDelegate
- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    for (CardCollectionViewCell *cell in self.cardCollectionView.visibleCells) {
        cell.imageScrollView.scrollEnabled = NO;
    }
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [self performSelector:@selector(scrollViewDidEndScrollingAnimation:) withObject:nil afterDelay:0.1];
}

-(void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    for (CardCollectionViewCell *cell in self.cardCollectionView.visibleCells) {
        cell.imageScrollView.scrollEnabled = YES;
    }
    if (self.status == CardViewStatusEdit) {
        self.buttonType = SaveButtonTypeDidSave;
        self.cardArray = [[DataBase sharedInstance] selectAllDataFromTable:@"mine"];
        [self.cardCollectionView reloadData];
    }
}

#pragma mark IFlySpeechSynthesizerDelegate
//结束代理
- (void) onCompleted:(IFlySpeechError *)error {
    if (![[error errorDesc] isEqualToString:@"服务正常"]) {
        [SVProgressHUD showErrorWithStatus:@"网络连接有问题"];
        [self performSelector:@selector(dismissProcessHud) withObject:nil afterDelay:1.5];
    }
    [self.playButton stopAnimating];
    self.cardCollectionView.userInteractionEnabled = YES;
}

#pragma mark CardCollectionViewCellDelegate
- (void)chinesePlayButtonClicked:(NSString *)chinese sender:(id)sender {
    [[VoiceHelper sharedInstance] startSpeaking:chinese withParamaters:nil];
    self.playButton = sender;
    [self.playButton startAnimating];
    self.cardCollectionView.userInteractionEnabled = NO;
}

- (void)englishPlayButtonClicked:(NSString *)english sender:(id)sender {
    [[VoiceHelper sharedInstance] startSpeaking:english withParamaters:nil];
    self.playButton = sender;
    [self.playButton startAnimating];
    self.cardCollectionView.userInteractionEnabled = NO;
}

- (void)imageBrowserDidEndScroll:(NSUInteger)index cell:(CardCollectionViewCell *)cell {
    [self.indexArray setObject:@(index) atIndexedSubscript:cell.indexPath];
    self.cardCollectionView.scrollEnabled = YES;
}

- (void)imageBrowserDidScroll:(CardCollectionViewCell *)cell {
    self.cardCollectionView.scrollEnabled = NO;
}

#pragma mark UITextFieldDelegate
- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    
    if ([string isEqualToString:@""])
    {
        return YES;
    }
    NSString * toBeString = [textField.text stringByReplacingCharactersInRange:range withString:string];
    NSUInteger maxLength = MAX_TEXT;
    if ([toBeString length] > maxLength) {
        textField.text = [toBeString substringToIndex:maxLength];
        return NO;
    }
    return YES;
}

#pragma override
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<NSString *,id> *)info{
    [super imagePickerController:picker didFinishPickingMediaWithInfo:info];
    if (self.originalImage) {
        [SVProgressHUD show];
        self.view.userInteractionEnabled = NO;
        Card *oldCard = [self.cardArray objectAtIndex:self.indexToDelete];
        __block Card *card = [[Card alloc] init];
        card.images = [NSArray arrayWithObjects:self.originalImage, nil];
        card.imageCounts = 1;
        [YTOperations identifyImage:[UIImage cutImage:self.originalImage size:CGSizeMake(200, 200)] ok:^(NSArray *array, NSError *error) {
            if (array.count > 0) {
                card.chinese = [(YTTagModel *)[array firstObject] tag_name];
                [NetworkManager translate2English:card.chinese ok:^(NSString *english, NSError *error) {
                    if (error) {
                        [SVProgressHUD showErrorWithStatus:@"网络连接有问题"];
                        [self performSelector:@selector(dismissProcessHud) withObject:nil afterDelay:1.5];
                    } else {
                        card.english = english;
                        NSMutableArray *array = [self.cardArray mutableCopy];
                        [array replaceObjectAtIndex:self.indexToDelete withObject:card];
                        self.cardArray = array;
                        if (self.status == CardViewStatusEdit) {
                            card.identifier = oldCard.identifier;
                            [[DataBase sharedInstance] deleteDataFromTable:@"mine" card:oldCard];
                            [[DataBase sharedInstance] insertDataIntoTable:@"mine" card:card];
                        }
                        [self.cardCollectionView reloadData];
                        [self dismissProcessHud];
                    }
                }];
            }
        }];
    }
}

#pragma mark custom method
- (void)setUpSubviews {
    self.navigationController.navigationBar.hidden = YES;
    self.cardCollectionView.scrollEnabled = YES;
    CardLayout *layout = [[CardLayout alloc] init];
    self.cardCollectionView.collectionViewLayout = layout;
    [self.cardCollectionView reloadData];
    
    [self.backButton addBlockForControlEvents:UIControlEventTouchUpInside block:^(id sender) {
        [self.navigationController popViewControllerAnimated:YES];
    }];
    
    [self.editButton addBlockForControlEvents:UIControlEventTouchUpInside block:^(id sender) {
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:nil message:@"卡片有误？编辑您的卡片" preferredStyle:UIAlertControllerStyleAlert];
        [alertController addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
            textField.placeholder = @"请输入中文";
            textField.delegate = self;
            textField.text = [(Card *)[self.cardArray objectAtIndex:self.indexToDelete] chinese];
        }];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(textViewEditChanged:) name:UITextFieldTextDidChangeNotification object:alertController.textFields[0]];
        UIAlertAction *action = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            NSMutableArray *textArray = [NSMutableArray array];
            for (UITextField *textField in alertController.textFields) {
                [textArray addObject:textField.text];
            }
            BOOL isNotChinese = NO;
            for (int i = 0; i < [(NSString *)textArray[0] length]; i++) {
                if (!IS_CH_SYMBOL([(NSString *)textArray[0] characterAtIndex:i])) {
                    isNotChinese = YES;
                }
            }
            if (!isNotChinese && [(NSString *)textArray[0] length] != 0) {
                __block Card *card = [[Card alloc] init];
                Card *oldCard = [self.cardArray objectAtIndex:self.indexToDelete];
                card = [[Card alloc] init];
                card.imageCounts = oldCard.imageCounts;
                card.chinese = textArray[0];
                NSMutableArray *imageArray = [NSMutableArray array];
                for (UIImage *image in oldCard.images) {
                    [imageArray addObject:image];
                }
                card.images = imageArray;
                [SVProgressHUD show];
                [NetworkManager translate2English:textArray[0] ok:^(NSString *english, NSError *error) {
                    if (error) {
                        [SVProgressHUD showErrorWithStatus:@"网络连接有问题"];
                        [self performSelector:@selector(dismissProcessHud) withObject:nil afterDelay:1.5];
                    } else {
                        card.english = english;
                        NSMutableArray *array = [self.cardArray mutableCopy];
                        [array replaceObjectAtIndex:self.indexToDelete withObject:card];
                        self.cardArray = array;
                        if (self.status == CardViewStatusEdit) {
                            card.identifier = oldCard.identifier;
                            [[DataBase sharedInstance] deleteDataFromTable:@"mine" card:oldCard];
                            [[DataBase sharedInstance] insertDataIntoTable:@"mine" card:card];
                        }
                        [self.cardCollectionView reloadData];
                        [self dismissProcessHud];
                    }
                }];
            } else {
                [SVProgressHUD showErrorWithStatus:@"输入有误"];
                [self performSelector:@selector(dismissProcessHud) withObject:nil afterDelay:1.2];
            }
        }];
        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        }];
        [alertController addAction:cancelAction];
        [alertController addAction:action];
        [self presentViewController:alertController animated:YES completion:nil];
    }];
    
    [self.saveButton addBlockForControlEvents:UIControlEventTouchUpInside block:^(id sender) {
        if (self.buttonType == SaveButtonTypeDidSave) {
            [[DataBase sharedInstance] deleteDataFromTable:@"mine" card:[self.cardArray objectAtIndex:self.indexToDelete]];
            self.buttonType = SaveButtonTypeNotSave;
        } else if (self.buttonType == SaveButtonTypeNotSave) {
            [[DataBase sharedInstance] insertDataIntoTable:@"mine" card:[self.cardArray objectAtIndex:self.indexToDelete]];
            self.buttonType = SaveButtonTypeDidSave;
            if (self.status == CardViewStatusCustom) {
                self.status = CardViewStatusEdit;
                self.cardArray = [NSArray arrayWithObjects:[[[DataBase sharedInstance] selectAllDataFromTable:@"mine"] lastObject], nil];
            }
        }
    }];
    
    [self.refreshButton addBlockForControlEvents:UIControlEventTouchUpInside block:^(id sender) {
        [self chooseImage];
    }];
    
    if (IS_IPHONE_5) {
        [self.cardCollectionView registerNib:[UINib nibWithNibName:@"CardCollectionViewCell_5s" bundle:nil] forCellWithReuseIdentifier:@"cardCell"];
    } else {
        [self.cardCollectionView registerNib:[UINib nibWithNibName:@"CardCollectionViewCell" bundle:nil] forCellWithReuseIdentifier:@"cardCell"];
    }
    
    self.indexArray = [NSMutableArray array];
    for (int i = 0; i < self.cardArray.count; i++) {
        [self.indexArray addObject:[NSNumber numberWithLong:0]];
    }
    
    if (self.status == CardViewStatusNormal) {
        self.saveButton.hidden = YES;
        self.editButton.hidden = YES;
        self.refreshButton.hidden = YES;
    } else if (self.status == CardViewStatusCustom) {
        self.saveButton.hidden = NO;
        self.editButton.hidden = NO;
        self.refreshButton.hidden = NO;
        self.buttonType = SaveButtonTypeNotSave;
    } else if (self.status == CardViewStatusEdit) {
        self.saveButton.hidden = NO;
        self.editButton.hidden = NO;
        self.refreshButton.hidden = NO;
        self.buttonType = SaveButtonTypeDidSave;
    }
}

-(void)textViewEditChanged:(NSNotification *)obj{
    UITextField *textField = (UITextField *)obj.object;
    NSString *toBeString = textField.text;
    NSString *lang = [[UITextInputMode currentInputMode] primaryLanguage];
    NSUInteger maxLength = MAX_TEXT;
    if ([lang isEqualToString:@"zh-Hans"]) {
        UITextRange *selectedRange = [textField markedTextRange];
        UITextPosition *position = [textField positionFromPosition:selectedRange.start offset:0];
        if (!position) {
            if (toBeString.length > maxLength) {
                textField.text = [toBeString substringToIndex:maxLength];
            }
        }
        else{
        }
    } else {
        if (toBeString.length > maxLength) {
            textField.text = [toBeString substringToIndex:maxLength];
        }
    }
}


- (void)dismissProcessHud {
    [SVProgressHUD dismiss];
    self.view.userInteractionEnabled = YES;
}

#pragma mark getters and setters
- (CardViewBindHelper *)bindHelper {
    if (_bindHelper == nil) {
        _bindHelper = [[CardViewBindHelper alloc] init];
    }
    return _bindHelper;
}

- (NSUInteger)indexToDelete {
    CardCollectionViewCell *cell = [[self.cardCollectionView visibleCells] objectAtIndex:0];
    _indexToDelete = [self.cardCollectionView indexPathForCell:cell].row;
    return _indexToDelete;
}

- (void)setButtonType:(SaveButtonType)buttonType {
    _buttonType = buttonType;
    if (buttonType == SaveButtonTypeDidSave) {
        [self.saveButton setImage:[UIImage imageNamed:@"icon_addcard"] forState:UIControlStateNormal];
    } else if (buttonType == SaveButtonTypeNotSave) {
        [self.saveButton setImage:[UIImage imageNamed:@"icon_add"] forState:UIControlStateNormal];
    }
}

@end
