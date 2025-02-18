//
//  BRTxDetailViewController.m
//  BreadWallet
//
//  Created by Aaron Voisine on 7/23/14.
//  Copyright (c) 2014 Aaron Voisine <voisine@gmail.com>
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

// Updated by Farrukh Askari <farrukh.askari01@gmail.com> on 3:22 PM 17/4/17.

#import "BRTxDetailViewController.h"
#import "BRTransaction.h"
#import "BRWalletManager.h"
#import "BRPeerManager.h"
#import "BRCopyLabel.h"
#import "NSString+Bitcoin.h"
#import "NSData+Bitcoin.h"
#import "BREventManager.h"

#define TRANSACTION_CELL_HEIGHT 75

@interface BRTxDetailViewController ()

@property (nonatomic, strong) NSArray *outputText, *outputDetail, *outputAmount;
@property (nonatomic, assign) int64_t sent, received;
@property (nonatomic, strong) id txStatusObserver;

@end

@implementation BRTxDetailViewController

- (void)viewDidLoad {
    [super viewDidLoad];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    if (! self.txStatusObserver) {
        self.txStatusObserver =
            [[NSNotificationCenter defaultCenter] addObserverForName:BRPeerManagerTxStatusNotification object:nil
            queue:nil usingBlock:^(NSNotification *note) {
                BRTransaction *tx = [[BRWalletManager sharedInstance].wallet
                                     transactionForHash:self.transaction.txHash];
                
                if (tx) self.transaction = tx;
                [self.tableView reloadData];
            }];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    if (self.txStatusObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.txStatusObserver];
    self.txStatusObserver = nil;
    
    [super viewWillDisappear:animated];
}

- (void)dealloc {
    if (self.txStatusObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.txStatusObserver];
}

- (void)setTransaction:(BRTransaction *)transaction {
    BRWalletManager *manager = [BRWalletManager sharedInstance];
    NSMutableArray *text = [NSMutableArray array], *detail = [NSMutableArray array], *amount = [NSMutableArray array];
    uint64_t fee = [manager.wallet feeForTransaction:transaction];
    NSUInteger outputAmountIndex = 0;
    
    _transaction = transaction;
    self.sent = [manager.wallet amountSentByTransaction:transaction];
    self.received = [manager.wallet amountReceivedFromTransaction:transaction];

    for (NSString *address in transaction.outputAddresses) {
        uint64_t amt = [transaction.outputAmounts[outputAmountIndex++] unsignedLongLongValue];
    
        if (address == (id)[NSNull null]) {
            if (self.sent > 0) {
                [text addObject:NSLocalizedString(@"unknown address", nil)];
                [detail addObject:NSLocalizedString(@"payment output", nil)];
                [amount addObject:@(-amt)];
            }
        }
        else if ([manager.wallet containsAddress:address]) {
            if (self.sent == 0 || self.received == self.sent) {
                [text addObject:address];
                [detail addObject:NSLocalizedString(@"wallet address", nil)];
                [amount addObject:@(amt)];
            }
        }
        else if (self.sent > 0) {
            [text addObject:address];
            [detail addObject:NSLocalizedString(@"payment address", nil)];
            [amount addObject:@(-amt)];
        }
    }

    if (self.sent > 0 && fee > 0 && fee != UINT64_MAX && text.count > 1) {
        NSString *fg_charge_address = @"";
#if BITCOIN_TESTNET
        fg_charge_address = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"FixedChargeDepositAccount_TEST_NET"];
#else
        fg_charge_address = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"FixedChargeDepositAccount"];
#endif
        
        long fg_charge_index = [text indexOfObject:fg_charge_address];
        [text removeObjectAtIndex:fg_charge_index];
        [detail removeObjectAtIndex:fg_charge_index];
        [amount removeObjectAtIndex:fg_charge_index];
//        uint64_t amt = [transaction.outputAmounts[fg_charge_index] unsignedLongLongValue];
        uint64_t financial_gate_charge = [manager getFinancialGateChargeAmount:@"0.50"];
        uint64_t cumulativeFee = fee + financial_gate_charge;
        [text addObject:@""];
        [detail addObject:NSLocalizedString(@"bitcoin network fee", nil)];
        [amount addObject:@(-cumulativeFee)];
    }
    
    self.outputText = text;
    self.outputDetail = detail;
    self.outputAmount = amount;
}

- (NSString *)updateBalance:(uint64_t)amount {
    
    BRWalletManager *manager = [BRWalletManager sharedInstance];
    
    manager.format.maximumFractionDigits = 8;
    NSString *stringWithoutSpaces = [[manager stringForAmount: amount]
                                     stringByReplacingOccurrencesOfString:@"ƀ" withString:@""];
    
    stringWithoutSpaces = [stringWithoutSpaces stringByReplacingOccurrencesOfString:@"," withString:@""];
    
    CGFloat btcAmount = [stringWithoutSpaces floatValue];
    
    NSString *btcAmountStr = [NSString stringWithFormat:@"BTC %.8f",btcAmount];
    
    return btcAmountStr;
}

- (void)setBackgroundForCell:(UITableViewCell *)cell indexPath:(NSIndexPath *)path {
    [cell viewWithTag:100].hidden = (path.row > 0);
    [cell viewWithTag:101].hidden = (path.row + 1 < [self tableView:self.tableView numberOfRowsInSection:path.section]);
}

#pragma mark: - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    // Return the number of sections.
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    // Return the number of rows in the section.
    switch (section) {
        case 0: return 3;
        case 1: return (self.sent > 0) ? self.outputText.count : self.transaction.inputAddresses.count;
        case 2: return (self.sent > 0) ? self.transaction.inputAddresses.count : self.outputText.count;
    }

    return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell;
    BRCopyLabel *detailLabel;
    UILabel *textLabel, *subtitleLabel, *amountLabel, *localCurrencyLabel;
    BRWalletManager *manager = [BRWalletManager sharedInstance];
    NSUInteger peerCount = [BRPeerManager sharedInstance].peerCount;
    NSUInteger relayCount = [[BRPeerManager sharedInstance] relayCountForTransaction:self.transaction.txHash];
    NSString *s;
    
    // Configure the cell...
    switch (indexPath.section) {
        case 0:
            switch (indexPath.row) {
                case 0:
                    cell = [tableView dequeueReusableCellWithIdentifier:@"IdCell" forIndexPath:indexPath];
                    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                    textLabel = (id)[cell viewWithTag:1];
                    detailLabel = (id)[cell viewWithTag:2];
                    [self setBackgroundForCell:cell indexPath:indexPath];
                    textLabel.text = NSLocalizedString(@"id:", nil);
                    s = [NSString hexWithData:[NSData dataWithBytes:self.transaction.txHash.u8
                                               length:sizeof(UInt256)].reverse];
                    detailLabel.text = [NSString stringWithFormat:@"%@\n%@", [s substringToIndex:s.length/2],
                                        [s substringFromIndex:s.length/2]];
                    detailLabel.copyableText = s;
                    break;
                    
                case 1:
                    cell = [tableView dequeueReusableCellWithIdentifier:@"TitleCell" forIndexPath:indexPath];
                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                    textLabel = (id)[cell viewWithTag:1];
                    detailLabel = (id)[cell viewWithTag:2];
                    subtitleLabel = (id)[cell viewWithTag:3];
                    [self setBackgroundForCell:cell indexPath:indexPath];
                    textLabel.text = NSLocalizedString(@"status:", nil);
                    subtitleLabel.text = nil;
                    
                    if (self.transaction.blockHeight != TX_UNCONFIRMED) {
                        detailLabel.text = [NSString stringWithFormat:NSLocalizedString(@"confirmed in block #%d", nil),
                                            self.transaction.blockHeight, self.txDateString];
                        subtitleLabel.text = self.txDateString;
                    }
                    else if (! [manager.wallet transactionIsValid:self.transaction]) {
                        detailLabel.text = NSLocalizedString(@"double spend", nil);
                    }
                    else if ([manager.wallet transactionIsPending:self.transaction]) {
                        detailLabel.text = NSLocalizedString(@"pending", nil);
                    }
                    else if (! [manager.wallet transactionIsVerified:self.transaction]) {
                        detailLabel.text = [NSString stringWithFormat:NSLocalizedString(@"seen by %d of %d peers", nil),
                                            relayCount, peerCount];
                    }
                    else detailLabel.text = NSLocalizedString(@"verified, waiting for confirmation", nil);
                    
                    break;
                    
                case 2:
                    cell = [tableView dequeueReusableCellWithIdentifier:@"TransactionCell"];
                    [self setBackgroundForCell:cell indexPath:indexPath];
                    textLabel = (id)[cell viewWithTag:1];
                    localCurrencyLabel = (id)[cell viewWithTag:5];

                    if (self.sent > 0 && self.sent == self.received) {
                        textLabel.text = [self updateBalance:self.sent];
                        localCurrencyLabel.text = [NSString stringWithFormat:@"(%@)", [manager localCurrencyStringForAmount:self.sent]];
                   
                    }
                    else {
                        textLabel.text = [self updateBalance:self.received - self.sent];
                        localCurrencyLabel.text = [NSString stringWithFormat:@"(%@)",
                                                   [manager localCurrencyStringForAmount:self.received - self.sent]];
                    }
                    
                    break;
                    
                default:
                    break;
            }
            
            break;
            
        case 1: // drop through
        case 2:
            if ((self.sent > 0 && indexPath.section == 1) || (self.sent == 0 && indexPath.section == 2)) {
                if ([self.outputText[indexPath.row] length] > 0) {
                    cell = [tableView dequeueReusableCellWithIdentifier:@"DetailCell" forIndexPath:indexPath];
                    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                }
                else cell = [tableView dequeueReusableCellWithIdentifier:@"SubtitleCell" forIndexPath:indexPath];

                detailLabel = (id)[cell viewWithTag:2];
                subtitleLabel = (id)[cell viewWithTag:3];
                amountLabel = (id)[cell viewWithTag:1];
                localCurrencyLabel = (id)[cell viewWithTag:5];
                detailLabel.text = self.outputText[indexPath.row];
                subtitleLabel.text = self.outputDetail[indexPath.row];
                amountLabel.text = [self updateBalance:[self.outputAmount[indexPath.row] longLongValue]];
                amountLabel.textColor = (self.sent > 0) ? [UIColor colorWithRed:1.0 green:0.33 blue:0.33 alpha:1.0] :
                                        [UIColor colorWithRed:0.0 green:0.75 blue:0.0 alpha:1.0];
                localCurrencyLabel.textColor = amountLabel.textColor;
                localCurrencyLabel.text = [NSString stringWithFormat:@"(%@)",
                                           [manager localCurrencyStringForAmount:[self.outputAmount[indexPath.row]
                                                                            longLongValue]]];
            }
            else if (self.transaction.inputAddresses[indexPath.row] != (id)[NSNull null]) {
                cell = [tableView dequeueReusableCellWithIdentifier:@"DetailCell" forIndexPath:indexPath];
                cell.selectionStyle = UITableViewCellSelectionStyleDefault;
                detailLabel = (id)[cell viewWithTag:2];
                subtitleLabel = (id)[cell viewWithTag:3];
                amountLabel = (id)[cell viewWithTag:1];
                localCurrencyLabel = (id)[cell viewWithTag:5];
                detailLabel.text = self.transaction.inputAddresses[indexPath.row];
                amountLabel.text = nil;
                localCurrencyLabel.text = nil;
                
                if ([manager.wallet containsAddress:self.transaction.inputAddresses[indexPath.row]]) {
                    subtitleLabel.text = NSLocalizedString(@"wallet address", nil);
                }
                else subtitleLabel.text = NSLocalizedString(@"spent address", nil);
            }
            else {
                cell = [tableView dequeueReusableCellWithIdentifier:@"DetailCell" forIndexPath:indexPath];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                detailLabel = (id)[cell viewWithTag:2];
                subtitleLabel = (id)[cell viewWithTag:3];
                amountLabel = (id)[cell viewWithTag:1];
                localCurrencyLabel = (id)[cell viewWithTag:5];
                detailLabel.text = NSLocalizedString(@"unknown address", nil);
                subtitleLabel.text = NSLocalizedString(@"spent input", nil);
                amountLabel.text = nil;
                localCurrencyLabel.text = nil;
            }

            [self setBackgroundForCell:cell indexPath:indexPath];
            break;
    }
    
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return nil;
        case 1: return (self.sent > 0) ? NSLocalizedString(@"to:", nil) : NSLocalizedString(@"from:", nil);
        case 2: return (self.sent > 0) ? NSLocalizedString(@"from:", nil) : NSLocalizedString(@"to:", nil);
    }
    
    return nil;
}

#pragma mark: - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    switch (indexPath.section) {
        case 0: return 44.0;
        case 1: return (self.sent > 0 && [self.outputText[indexPath.row] length] == 0) ? 40 : 60.0;
        case 2: return 60.0;
    }
    
    return 44.0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    NSString *sectionTitle = [self tableView:tableView titleForHeaderInSection:section];
    
    if (sectionTitle.length == 0) return 22.0;
    
    CGRect textRect = [sectionTitle boundingRectWithSize:CGSizeMake(self.view.frame.size.width - 30.0, CGFLOAT_MAX)
                options:NSStringDrawingUsesLineFragmentOrigin
                attributes:@{NSFontAttributeName:[UIFont fontWithName:@"Helvetica" size:17]} context:nil];
    
    return textRect.size.height + 12.0;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    UIView *headerview = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, self.view.frame.size.width,
                                                         [self tableView:tableView heightForHeaderInSection:section])];
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(15.0, 10.0, headerview.frame.size.width - 30.0,
                                                           headerview.frame.size.height - 12.0)];
    
    titleLabel.text = [self tableView:tableView titleForHeaderInSection:section];
    titleLabel.backgroundColor = [UIColor clearColor];
    titleLabel.font = [UIFont fontWithName:@"Helvetica" size:17];
    titleLabel.textColor = [UIColor colorWithRed:1.0 green:1.0 blue:1.0 alpha:0.5];
    titleLabel.numberOfLines = 0;
    headerview.backgroundColor = [UIColor clearColor];
    [headerview addSubview:titleLabel];
    
    return headerview;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSUInteger i = [self.tableView.indexPathsForVisibleRows indexOfObject:indexPath];
    UITableViewCell *cell = (i < self.tableView.visibleCells.count) ? self.tableView.visibleCells[i] : nil;
    BRCopyLabel *copyLabel = (id)[cell viewWithTag:2];
    [BREventManager saveEvent:@"tx_detail:copy_label"];
    
    copyLabel.selectedColor = [UIColor clearColor];
    if (cell.selectionStyle != UITableViewCellSelectionStyleNone) [copyLabel toggleCopyMenu];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end
