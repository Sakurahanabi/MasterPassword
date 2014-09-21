//
//  MPPreferencesViewController.m
//  MasterPassword-iOS
//
//  Created by Maarten Billemont on 04/06/12.
//  Copyright (c) 2012 Lyndir. All rights reserved.
//

#import <StoreKit/StoreKit.h>
#import "MPStoreViewController.h"
#import "MPiOSAppDelegate.h"
#import "MPAppDelegate_Key.h"
#import "MPAppDelegate_Store.h"
#import "UIColor+Expanded.h"
#import "MPPasswordsViewController.h"
#import "MPCoachmarkViewController.h"
#import "MPAppDelegate_InApp.h"

@interface MPStoreViewController()

@property(nonatomic, strong) NSNumberFormatter *currencyFormatter;

@end

@implementation MPStoreViewController

- (void)viewDidLoad {

    [super viewDidLoad];

    self.currencyFormatter = [NSNumberFormatter new];
    self.currencyFormatter.numberStyle = NSNumberFormatterCurrencyStyle;

    self.view.backgroundColor = [UIColor clearColor];
}

- (void)viewWillAppear:(BOOL)animated {

    [super viewWillAppear:animated];

    self.tableView.contentInset = UIEdgeInsetsMake( 64, 0, 49, 0 );

    [self reloadCellsHiding:self.allCellsBySection[0] showing:nil];
    [self.allCellsBySection[0] enumerateObjectsUsingBlock:^(MPStoreProductCell *cell, NSUInteger idx, BOOL *stop) {
        if ([cell isKindOfClass:[MPStoreProductCell class]]) {
            cell.purchasedIndicator.alpha = 0;
            [cell.activityIndicator stopAnimating];
        }
    }];

    [[MPiOSAppDelegate get] observeKeyPath:@"products" withBlock:^(id from, id to, NSKeyValueChange cause, id _self) {
        if (NSNullToNil( to ))
            PearlMainQueue( ^{
                [self updateWithProducts:to];
            } );
    }];
    [[MPiOSAppDelegate get] observeKeyPath:@"paymentTransactions" withBlock:^(id from, id to, NSKeyValueChange cause, id _self) {
        if (NSNullToNil( to ))
            PearlMainQueue( ^{
                [self updateWithTransactions:to];
            } );
    }];
    [[NSNotificationCenter defaultCenter] addObserverForName:NSUserDefaultsDidChangeNotification object:nil
                                                       queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
                [self updateWithProducts:[MPiOSAppDelegate get].products];
            }];

    [[MPiOSAppDelegate get] updateProducts];
}

#pragma mark - UITableViewDelegate

- (MPStoreProductCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {

    MPStoreProductCell *cell = (MPStoreProductCell *)[super tableView:tableView cellForRowAtIndexPath:indexPath];
    if (indexPath.section == 0)
        cell.selectionStyle = [[MPiOSAppDelegate get] isPurchased:[self productForCell:cell].productIdentifier]?
                              UITableViewCellSelectionStyleDefault: UITableViewCellSelectionStyleNone;

    if (cell.selectionStyle != UITableViewCellSelectionStyleNone) {
        cell.selectedBackgroundView = [[UIView alloc] initWithFrame:cell.bounds];
        cell.selectedBackgroundView.backgroundColor = [UIColor colorWithRGBAHex:0x78DDFB33];
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {

    if (![SKPaymentQueue canMakePayments]) {
        [PearlAlert showAlertWithTitle:@"Store Not Set Up" message:
                             @"Try logging using the App Store or from Settings."
                             viewStyle:UIAlertViewStyleDefault initAlert:nil
                     tappedButtonBlock:nil cancelTitle:@"Thanks" otherTitles:nil];
        return;
    }

    MPStoreProductCell *cell = (MPStoreProductCell *)[self tableView:tableView cellForRowAtIndexPath:indexPath];
    SKProduct *product = [self productForCell:cell];

    if (product)
        [[SKPaymentQueue defaultQueue] addPayment:[SKPayment paymentWithProduct:product]];

    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

#pragma mark - Actions

- (IBAction)restorePurchases:(id)sender {

    [PearlAlert showAlertWithTitle:@"Restore Previous Purchases" message:
                    @"This will check with Apple to find and activate any purchases you made from other devices."
                         viewStyle:UIAlertViewStyleDefault initAlert:nil
                 tappedButtonBlock:^(UIAlertView *alert, NSInteger buttonIndex) {
                     if (buttonIndex == [alert cancelButtonIndex])
                         return;

                     [[SKPaymentQueue defaultQueue] restoreCompletedTransactions];
                 } cancelTitle:@"Cancel" otherTitles:@"Find Purchases", nil];
}

#pragma mark - Private

- (SKProduct *)productForCell:(MPStoreProductCell *)cell {

    for (SKProduct *product in [MPiOSAppDelegate get].products)
        if ([self cellForProductIdentifier:product.productIdentifier] == cell)
            return product;

    return nil;
}

- (MPStoreProductCell *)cellForProductIdentifier:(NSString *)productIdentifier {

    if ([productIdentifier isEqualToString:MPProductGenerateLogins])
        return self.generateLoginCell;
    if ([productIdentifier isEqualToString:MPProductGenerateAnswers])
        return self.generateAnswersCell;

    return nil;
}

- (void)updateWithProducts:(NSArray *)products {

    NSMutableArray *showCells = [NSMutableArray array];
    NSMutableArray *hideCells = [NSMutableArray array];
    [hideCells addObjectsFromArray:self.allCellsBySection[0]];

    for (SKProduct *product in products) {
        [self showCellForProductWithIdentifier:MPProductGenerateLogins ifProduct:product showingCells:showCells];
        [self showCellForProductWithIdentifier:MPProductGenerateAnswers ifProduct:product showingCells:showCells];
    }

    [hideCells removeObjectsInArray:showCells];
    if ([self.tableView numberOfRowsInSection:0])
        [self updateCellsHiding:hideCells showing:showCells animation:UITableViewRowAnimationAutomatic];
    else
        [self updateCellsHiding:hideCells showing:showCells animation:UITableViewRowAnimationNone];
}

- (void)showCellForProductWithIdentifier:(NSString *)productIdentifier ifProduct:(SKProduct *)product
                            showingCells:(NSMutableArray *)showCells {

    if (![product.productIdentifier isEqualToString:productIdentifier])
        return;

    MPStoreProductCell *cell = [self cellForProductIdentifier:productIdentifier];
    [showCells addObject:cell];

    self.currencyFormatter.locale = product.priceLocale;
    BOOL purchased = [[MPiOSAppDelegate get] isPurchased:productIdentifier];
    cell.priceLabel.text = purchased? @"": [self.currencyFormatter stringFromNumber:product.price];
    cell.purchasedIndicator.alpha = purchased? 1: 0;
}

- (void)updateWithTransactions:(NSArray *)transactions {

    for (SKPaymentTransaction *transaction in transactions) {
        MPStoreProductCell *cell = [self cellForProductIdentifier:transaction.payment.productIdentifier];
        if (!cell)
            continue;

        switch (transaction.transactionState) {
            case SKPaymentTransactionStatePurchasing:
                [cell.activityIndicator startAnimating];
                break;
            case SKPaymentTransactionStatePurchased:
                [cell.activityIndicator stopAnimating];
                break;
            case SKPaymentTransactionStateFailed:
                [cell.activityIndicator stopAnimating];
                break;
            case SKPaymentTransactionStateRestored:
                [cell.activityIndicator stopAnimating];
                break;
            case SKPaymentTransactionStateDeferred:
                [cell.activityIndicator startAnimating];
                break;
        }
    }
}

@end

@implementation MPStoreProductCell
@end